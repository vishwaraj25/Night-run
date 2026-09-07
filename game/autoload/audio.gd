extends Node
## Autoload: res://autoload/audio.gd -> "Audio"
##
## One place that owns sound, so nothing else has to manage players or worry
## about how often it is calling. Two kinds of sound:
##
##   play(name)        one-shots, from a fixed pool of players
##   loop(name) / stop_loop(name)   sustained things (laser, flamethrower)
##
## Three problems this solves that a bare AudioStreamPlayer per caller does not:
##
## 1. A machine gun at a 0.13s fire rate, times several enemies, times impact
##    sparks, is dozens of overlapping voices a second. The pool is capped, and
##    the oldest voice is stolen when it runs out, so audio can never be the
##    thing that stalls the game.
## 2. The same sound firing twice in the same millisecond is not twice as loud,
##    it is a phasing artefact. Each sound has a minimum retrigger gap.
##    Without it, the double MG's two barrels sounded like one clipped click.
## 3. Browsers refuse to start audio before the user interacts with the page.
##    Nothing here needs special handling for that -- the menu takes a click
##    before the game starts -- but it is why sound must never be load-bearing
##    for anything, and it is not: this is entirely cosmetic.

const SFX_DIR := "res://assets/sfx/"
const POOL_SIZE := 16

## Per-sound minimum gap between retriggers, in seconds. Anything not listed
## uses DEFAULT_GAP. These are tuned to each sound's own length -- a 0.07s
## gunshot can retrigger far faster than a 1.2s explosion.
const DEFAULT_GAP := 0.04
const RETRIGGER_GAP := {
	"shoot_mg": 0.05,
	"shoot_double": 0.06,
	"hit_enemy": 0.05,
	"enemy_shoot": 0.07,
	"explosion": 0.09,
	"explosion_big": 0.4,
	"player_hurt": 0.25,
	"jump": 0.12,
	"enemy_down": 0.1,
}

## Per-sound level. Frequent sounds sit low so the rare ones can be heard over
## them -- gunfire is constant and must not drown out taking a hit.
const VOLUME_DB := {
	"shoot_mg": -14.0,
	"shoot_double": -13.0,
	"hit_enemy": -15.0,
	"enemy_shoot": -13.0,
	"laser_loop": -12.0,
	"flame_loop": -13.0,
	"boss_laser_loop": -8.0,
	"explosion": -6.0,
	"explosion_big": -3.0,
	"player_hurt": -4.0,
	"jump": -16.0,
	"pickup": -6.0,
	"checkpoint": -5.0,
	"shield_up": -9.0,
	"deflect": -4.0,
	"boss_charge": -7.0,
	"menu_click": -10.0,
	"enemy_down": -11.0,
}

signal muted_changed(is_muted: bool)

var muted: bool = false

var _streams: Dictionary = {}       # name -> AudioStream
var _pool: Array[AudioStreamPlayer] = []
var _next_player: int = 0
var _last_played: Dictionary = {}   # name -> msec
var _loops: Dictionary = {}         # name -> AudioStreamPlayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # keeps working while paused
	_load_streams()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_pool.append(p)

func _load_streams() -> void:
	var dir := DirAccess.open(SFX_DIR)
	if not dir:
		push_warning("Audio: no sfx directory at %s" % SFX_DIR)
		return
	for file in dir.get_files():
		# Godot hands back the imported name; both are worth trying.
		var base := file.get_basename()
		if base.ends_with(".wav"):
			base = base.get_basename()
		var stream: AudioStream = load(SFX_DIR + base + ".wav")
		if stream:
			_streams[base] = stream

## Fire and forget. Unknown names warn once rather than crashing -- a missing
## sound should never take the game with it.
func play(sound: String, pitch_variation: float = 0.06) -> void:
	if muted or not _streams.has(sound):
		if not _streams.has(sound):
			push_warning("Audio: unknown sound '%s'" % sound)
		return

	var now := Time.get_ticks_msec()
	var gap: float = RETRIGGER_GAP.get(sound, DEFAULT_GAP)
	if now - int(_last_played.get(sound, -99999)) < int(gap * 1000.0):
		return
	_last_played[sound] = now

	var p := _pool[_next_player]
	_next_player = (_next_player + 1) % POOL_SIZE
	p.stream = _streams[sound]
	p.volume_db = VOLUME_DB.get(sound, -8.0)
	# A little pitch scatter, so a repeated sound doesn't turn into a machine
	# that is obviously playing one file over and over.
	p.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
	p.play()

## Sustained sounds. Calling loop() on something already looping does nothing,
## so callers can hold it down every frame without thinking about it.
func loop(sound: String) -> void:
	if muted or not _streams.has(sound) or _loops.has(sound):
		return
	var p := AudioStreamPlayer.new()
	p.bus = "Master"
	p.stream = _streams[sound]
	p.volume_db = VOLUME_DB.get(sound, -10.0)
	if p.stream is AudioStreamWAV:
		(p.stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	add_child(p)
	p.play()
	_loops[sound] = p

func stop_loop(sound: String) -> void:
	if not _loops.has(sound):
		return
	var p: AudioStreamPlayer = _loops[sound]
	_loops.erase(sound)
	if is_instance_valid(p):
		p.stop()
		p.queue_free()

func stop_all_loops() -> void:
	for sound in _loops.keys():
		stop_loop(sound)

func set_muted(value: bool) -> void:
	muted = value
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), muted)
	if muted:
		stop_all_loops()
	muted_changed.emit(muted)

func toggle_mute() -> void:
	set_muted(not muted)

func _unhandled_input(event: InputEvent) -> void:
	# A mute key, because this is going out as a link and someone will open it
	# with their volume up in a quiet room.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		toggle_mute()
