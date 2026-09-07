extends CanvasLayer
## Self-contained pause toggle: lives entirely on this ALWAYS-mode node so
## nothing else in the tree needs its process_mode touched. Setting the
## *parent* Level to ALWAYS instead would cascade to every child still on
## the default INHERIT mode (car, enemies, spawners...), which would keep
## running during "pause" — exactly backwards.

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_tree().paused = not get_tree().paused
		visible = get_tree().paused
