extends Node2D
## Level shell: owns the run's start/end and the checkpoint respawn loop.
##
## Dying used to drop you straight back to the main menu, which meant replaying
## a 27,000px level from the street to retry anything near the end. Now death
## returns you to the last checkpoint you walked through, with the immediate
## area cleared so you don't respawn into the shot that killed you.

const RESPAWN_DELAY := 1.2   ## long enough for the death animation to read
const CLEAR_RADIUS := 900.0  ## enemies this close to the respawn point are removed

## Progress is reported every this many pixels of FURTHEST advance, and each
## report is flushed immediately. That immediacy is the whole point: a browser
## game is usually left by closing the tab, where no reliable "goodbye" event
## exists -- so the drop-off has to already be on the server before they go.
## 2000px over a 27,400px level is ~14 reports on a full run: enough for a
## clean histogram, small enough to be nothing.
const PROGRESS_STEP := 2000.0

@onready var player: Node2D = $PlayerCyborg

var _respawn_point: Vector2
var _has_checkpoint: bool = false
var _next_progress_x: float = 0.0

func _ready() -> void:
	GameState.start_run()
	_respawn_point = player.global_position # the level start is the implicit first one
	EventBus.player_died.connect(_on_player_died)
	EventBus.boss_defeated.connect(_on_boss_defeated)
	EventBus.checkpoint_reached.connect(_on_checkpoint_reached)
	_next_progress_x = player.global_position.x + PROGRESS_STEP

func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		return
	if player.global_position.x >= _next_progress_x:
		# Round it: the exact pixel is noise, and a rounded value is one less
		# thing that could ever be mistaken for something precise about a person.
		Telemetry.log_event("progress", {"x": snappedf(_next_progress_x, PROGRESS_STEP)})
		Telemetry.flush_now()
		while player.global_position.x >= _next_progress_x:
			_next_progress_x += PROGRESS_STEP

func _on_checkpoint_reached(respawn_position: Vector2) -> void:
	_respawn_point = respawn_position
	_has_checkpoint = true

func _on_player_died(_reason: String) -> void:
	await get_tree().create_timer(RESPAWN_DELAY).timeout
	if not is_instance_valid(player):
		get_tree().change_scene_to_file("res://ui/main_menu.tscn")
		return

	# Anything still alive around the respawn point goes, including whatever
	# killed you. Static traps stay -- they are part of the level's geometry
	# and clearing them would erase a hazard permanently.
	for e in get_tree().get_nodes_in_group("spawned_enemy"):
		if is_instance_valid(e) and e.global_position.distance_to(_respawn_point) < CLEAR_RADIUS:
			e.queue_free()

	# If the boss was up, that fight restarts from the top rather than
	# resuming against a half-dead boss -- otherwise dying repeatedly would
	# whittle it down for free.
	var boss_spawner := get_node_or_null("BossSpawner")
	if boss_spawner and boss_spawner.has_method("restart_encounter"):
		boss_spawner.restart_encounter()

	player.respawn(_respawn_point)
	EventBus.player_respawned.emit(_respawn_point)

func _on_boss_defeated() -> void:
	await get_tree().create_timer(2.0).timeout
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
