extends CanvasLayer
## Self-contained pause toggle: lives entirely on this ALWAYS-mode node so
## nothing else in the tree needs its process_mode touched. Setting the
## *parent* Level to ALWAYS instead would cascade to every child still on
## the default INHERIT mode (car, enemies, spawners...), which would keep
## running during "pause" — exactly backwards.
##
## Polls the action rather than listening for the event. TouchScreenButton
## drives input through Input.action_press, which sets the action state without
## sending an event down the _unhandled_input chain -- so the old event-based
## version could never have been triggered by an on-screen pad, only by a key.
## Polling is the one path both a key and a pad actually take.

const RESUME_SIZE := Vector2(230.0, 62.0)
const MUTE_SIZE := Vector2(230.0, 54.0)

@onready var dim: ColorRect = $Dim
@onready var label: Label = $Label

var _resume: Button
var _mute: Button

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	# Real buttons, because on a phone there is no Escape key to resume with
	# and no M to mute with. They work with a mouse on desktop too.
	_resume = _make_button("Resume")
	_resume.pressed.connect(_toggle)
	_mute = _make_button("Sound: on")
	_mute.pressed.connect(_on_mute_pressed)

	Audio.muted_changed.connect(_refresh_mute_label)
	_refresh_mute_label(Audio.muted)

	get_viewport().size_changed.connect(_relayout)
	_relayout()

func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	add_child(b)
	return b

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("pause"):
		_toggle()

func _toggle() -> void:
	Audio.play("menu_click")
	get_tree().paused = not get_tree().paused
	visible = get_tree().paused
	# A sustained weapon or the boss's beam can be mid-loop when the world
	# stops; nothing is left driving it while paused, so it would hold one
	# note under the pause screen.
	if get_tree().paused:
		Audio.stop_all_loops()

func _on_mute_pressed() -> void:
	Audio.toggle_mute()

func _refresh_mute_label(is_muted: bool) -> void:
	if _mute:
		_mute.text = "Sound: off" if is_muted else "Sound: on"

## Everything here was authored at fixed 960x540 offsets: the dim panel stopped
## at x=960, so on a wider phone view the right-hand strip of the game stayed
## bright and unpaused-looking, and the label sat left of centre.
func _relayout() -> void:
	var view := get_viewport().get_visible_rect().size
	if view.x <= 0.0 or view.y <= 0.0:
		return

	dim.position = Vector2.ZERO
	dim.size = view

	label.size = Vector2(300.0, 44.0)
	label.position = Vector2((view.x - label.size.x) * 0.5, view.y * 0.5 - 110.0)

	_resume.size = RESUME_SIZE
	_resume.position = Vector2((view.x - RESUME_SIZE.x) * 0.5, view.y * 0.5 - 30.0)
	_mute.size = MUTE_SIZE
	_mute.position = Vector2((view.x - MUTE_SIZE.x) * 0.5, view.y * 0.5 + 46.0)
