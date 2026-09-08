extends Node
## Autoload singleton: res://autoload/game_state.gd -> "GameState"
## Tracks the current run's score/coins/health, and wires EventBus
## signals through to Telemetry so gameplay code never calls
## Telemetry directly.

var score: int = 0
var coins: int = 0
var run_start_time: float = 0.0

func _ready() -> void:
	EventBus.item_collected.connect(_on_item_collected)
	EventBus.enemy_defeated.connect(_on_enemy_defeated)
	EventBus.boss_defeated.connect(_on_boss_defeated)
	EventBus.player_died.connect(_on_player_died)
	EventBus.shield_deflected.connect(_on_shield_deflected)
	EventBus.double_jumped.connect(_on_double_jumped)

func start_run() -> void:
	score = 0
	coins = 0
	run_start_time = Time.get_unix_time_from_system()
	Telemetry.log_event("run_start", {})

func _on_item_collected(item_name: String) -> void:
	coins += 1
	Telemetry.log_event("item_collected", {"item": item_name})

func _on_enemy_defeated(enemy_name: String, position: Vector2) -> void:
	score += 10
	Telemetry.log_event("enemy_defeated", {"enemy": enemy_name, "x": position.x})

func _on_boss_defeated() -> void:
	score += 500
	Telemetry.log_event("boss_defeated", {"score": score})

func _on_player_died(reason: String) -> void:
	var duration := Time.get_unix_time_from_system() - run_start_time
	Telemetry.log_run_end(reason, score, duration, _player_x())

func _on_shield_deflected(perfect: bool) -> void:
	Telemetry.log_event("shield_deflect", {"perfect": perfect})

func _on_double_jumped() -> void:
	Telemetry.log_event("double_jump", {})


## Where the player was, for the events that care. Looked up rather than
## passed in, so nothing else has to thread a position through to get here.
func _player_x() -> float:
	var p := get_tree().get_first_node_in_group("player")
	return p.global_position.x if p else 0.0
