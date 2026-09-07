extends Node
## Autoload singleton: res://autoload/telemetry.gd -> "Telemetry"
##
## Buffers gameplay events in memory and flushes them to the analytics
## endpoint in batches, so a busy combat moment never blocks on a network
## round-trip. Anonymous by design: the only identifier is a per-run
## sessionId generated client-side, never tied to an account.

## Off until there is a real endpoint behind ENDPOINT_URL. Left in place
## rather than deleted because the queueing, batching, retry and offline
## persistence all work -- the only thing missing is somewhere to send to.
## Flip this to true once backend/ is deployed and ENDPOINT_URL is real.
##
## While it was on it fired at a placeholder host every few seconds and
## retried each failure, which stalled headless runs for minutes at a time
## and filled the log with retry warnings.
@export var enabled: bool = false

const ENDPOINT_URL := "https://your-project.example.com/api/events"
const FLUSH_INTERVAL_SEC := 8.0        # time-based flush
const FLUSH_BATCH_SIZE := 20           # size-based flush (whichever comes first)
const MAX_QUEUE_SIZE := 500            # hard cap so a long offline stretch can't leak memory
const MAX_RETRIES := 3
const PERSIST_PATH := "user://telemetry_pending.json"
const PLAYER_ID_PATH := "user://player_id.txt"

## The complete list of what this game is allowed to send, mirroring the
## server's allow-list in backend/api/events.js. Enforced on BOTH sides on
## purpose: the server's copy is what actually protects the database, and this
## copy is what guarantees the shipped game never even attempts to send
## anything else. A key not named here is dropped before it reaches the queue.
const ALLOWED_EVENTS := {
	"run_start": [],
	"run_end": ["reason", "score", "duration_sec", "x"],
	"item_collected": ["item"],
	"enemy_defeated": ["enemy", "x"],
	"boss_defeated": ["score"],
	"checkpoint_reached": ["x"],
	"player_died": ["reason", "x"],
	# The drop-off signal. Emitted and flushed every 2000px of furthest
	# progress, which matters because most people leave a browser game by
	# closing the tab -- no death, no quit, no unload handler you can rely on.
	# Because each milestone was already sent, the last one recorded IS where
	# they stopped. Without this, the most common way people leave is invisible.
	"progress": ["x"],
	"menu_click": ["button"],
}

## Anonymous, and that word is doing real work: this is a random UUID the game
## makes up on first launch and keeps in its own save file. It is not derived
## from the device, the OS, an account, or anything about the person, and
## clearing the game's data produces a completely new one. It is the ONLY
## identifier that ever leaves the machine.
var player_id: String = ""
## A fresh id per launch, so "three short runs" and "one long run" can be told
## apart without needing to know anything else.
var session_id: String = ""
var _queue: Array = []
var _http: HTTPRequest
var _flush_timer: Timer
var _in_flight: bool = false
var _retry_count: int = 0

func _ready() -> void:
	session_id = _generate_session_id()
	player_id = _load_or_create_player_id()
	if not enabled:
		return

	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)

	_flush_timer = Timer.new()
	_flush_timer.wait_time = FLUSH_INTERVAL_SEC
	_flush_timer.autostart = true
	_flush_timer.timeout.connect(_flush)
	add_child(_flush_timer)

	_load_persisted_queue()
	log_event("run_start", {})

	get_tree().auto_accept_quit = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		_persist_queue()
		if what == NOTIFICATION_WM_CLOSE_REQUEST:
			get_tree().quit()

## Public API -----------------------------------------------------------

func log_event(event_name: String, payload: Dictionary = {}) -> void:
	if not enabled:
		return
	if not ALLOWED_EVENTS.has(event_name):
		push_warning("Telemetry: refusing to send unknown event '%s'" % event_name)
		return
	if _queue.size() >= MAX_QUEUE_SIZE:
		_queue.pop_front() # drop oldest rather than grow unbounded

	_queue.append({
		"name": event_name,
		"ts": Time.get_unix_time_from_system(),
		"payload": _filter_payload(event_name, payload),
	})

	if _queue.size() >= FLUSH_BATCH_SIZE:
		_flush()

func log_run_end(reason: String, score: int, run_duration_sec: float, x: float = 0.0) -> void:
	log_event("run_end", {
		"reason": reason, "score": score, "duration_sec": run_duration_sec, "x": x,
	})
	_flush() # run end is high-value, don't wait for the timer

## Send whatever is queued right now, rather than waiting for the timer.
## Used for the progress milestones, which are worthless if they are still
## sitting in a buffer when the tab closes.
func flush_now() -> void:
	_flush()

## Internals --------------------------------------------------------------

func _flush() -> void:
	if not enabled:
		return
	if _in_flight or _queue.is_empty():
		return

	_in_flight = true
	var batch := _queue.duplicate(true)

	var body := JSON.stringify({
		"playerId": player_id,
		"sessionId": session_id,
		"events": batch,
	})
	var headers := ["Content-Type: application/json"]

	var err := _http.request(ENDPOINT_URL, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_in_flight = false
		return

	# Optimistically clear now; on failure we re-queue via _on_request_completed.
	_queue = _queue.slice(batch.size())
	_pending_batch = batch

var _pending_batch: Array = []

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_in_flight = false

	var success := result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300
	if success:
		_retry_count = 0
		_pending_batch = []
	else:
		_retry_count += 1
		if _retry_count <= MAX_RETRIES:
			# Put the failed batch back at the front of the queue for the next flush.
			_queue = _pending_batch + _queue
		else:
			# Give up on this batch to avoid an infinite retry loop; log locally only.
			push_warning("Telemetry: dropping batch after %d failed attempts" % MAX_RETRIES)
			_retry_count = 0
		_pending_batch = []

func _generate_session_id() -> String:
	# RFC4122-ish v4 UUID, sufficient for an anonymous per-run identifier.
	var bytes := []
	for i in range(16):
		bytes.append(randi() % 256)
	bytes[6] = (bytes[6] & 0x0F) | 0x40
	bytes[8] = (bytes[8] & 0x3F) | 0x80
	var hex := ""
	for b in bytes:
		hex += "%02x" % b
	return "%s-%s-%s-%s-%s" % [hex.substr(0,8), hex.substr(8,4), hex.substr(12,4), hex.substr(16,4), hex.substr(20,12)]

func _persist_queue() -> void:
	if _queue.is_empty():
		return
	var f := FileAccess.open(PERSIST_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_queue))

func _load_persisted_queue() -> void:
	if not FileAccess.file_exists(PERSIST_PATH):
		return
	var f := FileAccess.open(PERSIST_PATH, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Array:
		_queue = parsed + _queue
	DirAccess.remove_absolute(PERSIST_PATH)


## Keeps only the keys this event is allowed to carry. Belt and braces with
## the server's own allow-list: a caller that adds a field here -- deliberately
## or by accident -- has it dropped at the source rather than sent and rejected.
func _filter_payload(event_name: String, payload: Dictionary) -> Dictionary:
	var allowed: Array = ALLOWED_EVENTS[event_name]
	var out := {}
	for key in payload:
		if key in allowed:
			out[key] = payload[key]
		else:
			push_warning("Telemetry: dropping disallowed key '%s' on '%s'" % [key, event_name])
	return out

## Read the anonymous id back, or mint one on first launch. Stored in user://,
## which is the game's own sandboxed save directory on every platform -- app
## storage on Android, the browser's origin-private storage on web. Nothing
## outside this game can read it, and uninstalling takes it with you.
func _load_or_create_player_id() -> String:
	if FileAccess.file_exists(PLAYER_ID_PATH):
		var f := FileAccess.open(PLAYER_ID_PATH, FileAccess.READ)
		if f:
			var existing := f.get_as_text().strip_edges()
			f.close()
			if existing.length() == 36:
				return existing
	var fresh := _generate_session_id()
	var w := FileAccess.open(PLAYER_ID_PATH, FileAccess.WRITE)
	if w:
		w.store_string(fresh)
		w.close()
	return fresh

## Forget this player: new id, queue dropped. Wired to nothing yet -- it is
## here so "delete my data" is one call away when there is a settings screen.
func reset_identity() -> void:
	_queue.clear()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PLAYER_ID_PATH))
	player_id = _load_or_create_player_id()
