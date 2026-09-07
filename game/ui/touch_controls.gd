extends CanvasLayer
## On-screen controls for touch devices.
##
## These drive the same input actions the keyboard does, so no gameplay code
## knows or cares that a finger is doing the pressing -- and the Contra aim
## scheme (forward along your facing, Up to angle up, Down in the air to angle
## down) maps onto buttons without needing a stick.
##
## TouchScreenButton, not Button: it handles genuine multitouch, so holding
## right + fire + jump at once works. A Control-based button set drops presses
## the moment two fingers are down, which is every second of this game.
##
## Laid out from the live viewport size rather than fixed coordinates, because
## the project now stretches with "expand" -- a 20:9 phone gets a wider view
## than a 16:9 one, and the pads have to follow the real edges.

const PAD_RADIUS := 46.0
const EDGE_PAD := 34.0

## Bottom corners, thumbs-first: movement left, actions right. Jump sits
## nearest the right thumb's rest position and shield next to it, because the
## perfect-deflect window is 0.2s -- it cannot be behind an awkward reach.
const LAYOUT := [
	{"action": "move_backward", "label": "<",  "corner": "left",  "col": 0, "row": 0},
	{"action": "move_forward",  "label": ">",  "corner": "left",  "col": 1, "row": 0},
	{"action": "lane_up",       "label": "^",  "corner": "left",  "col": 1, "row": 1},
	{"action": "crouch",        "label": "v",  "corner": "left",  "col": 0, "row": 1},
	{"action": "fire",          "label": "FIRE",   "corner": "right", "col": 1, "row": 0},
	{"action": "jump",          "label": "JUMP",   "corner": "right", "col": 0, "row": 0},
	{"action": "shield",        "label": "SHIELD", "corner": "right", "col": 0, "row": 1},
]

@export var force_visible: bool = false ## turn on to lay the pads out on desktop

var _buttons: Array = []
var _painter: Node2D

func _ready() -> void:
	layer = 20 # above the HUD
	if not force_visible and not _is_touch_device():
		queue_free()
		return

	_painter = Node2D.new()
	_painter.draw.connect(_draw_pads)
	add_child(_painter)

	for spec in LAYOUT:
		var b := TouchScreenButton.new()
		b.action = spec["action"]
		b.shape = CircleShape2D.new()
		(b.shape as CircleShape2D).radius = PAD_RADIUS
		b.visibility_mode = TouchScreenButton.VISIBILITY_ALWAYS
		add_child(b)
		_buttons.append({"node": b, "spec": spec})

	get_viewport().size_changed.connect(_relayout)
	_relayout()

## Touch pads on a desktop build would be dead weight over the play area, and
## a phone with a keyboard attached is not a case worth designing around.
func _is_touch_device() -> bool:
	return DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")

func _relayout() -> void:
	var size := get_viewport().get_visible_rect().size
	# Safe area, so the pads clear a notch, a punch-hole or a gesture bar.
	var safe := DisplayServer.get_display_safe_area()
	var screen := DisplayServer.screen_get_size()
	var inset_l := 0.0
	var inset_r := 0.0
	var inset_b := 0.0
	if screen.x > 0 and screen.y > 0 and safe.size.x > 0:
		inset_l = float(safe.position.x) / float(screen.x) * size.x
		inset_r = float(screen.x - safe.end.x) / float(screen.x) * size.x
		inset_b = float(screen.y - safe.end.y) / float(screen.y) * size.y

	var step := PAD_RADIUS * 2.2
	for entry in _buttons:
		var spec: Dictionary = entry["spec"]
		var col: float = float(spec["col"])
		var row: float = float(spec["row"])
		var x: float
		if spec["corner"] == "left":
			x = EDGE_PAD + inset_l + PAD_RADIUS + col * step
		else:
			x = size.x - EDGE_PAD - inset_r - PAD_RADIUS - col * step
		var y: float = size.y - EDGE_PAD - inset_b - PAD_RADIUS - row * step
		# TouchScreenButton's shape is centred on its position.
		entry["node"].position = Vector2(x, y)
	if _painter:
		_painter.queue_redraw()

func _draw_pads() -> void:
	var font := ThemeDB.fallback_font
	for entry in _buttons:
		var pos: Vector2 = entry["node"].position
		var label: String = entry["spec"]["label"]
		# Deliberately low contrast: these sit over the play area for the whole
		# game, so they have to be findable by thumb without competing with the
		# enemies for attention.
		_painter.draw_circle(pos, PAD_RADIUS, Color(0.05, 0.06, 0.09, 0.38))
		_painter.draw_arc(pos, PAD_RADIUS, 0.0, TAU, 28, Color(0.45, 0.85, 1.0, 0.55), 2.0, true)
		var fs := 15 if label.length() > 2 else 22
		var dims := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		_painter.draw_string(font, pos + Vector2(-dims.x * 0.5, dims.y * 0.32), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.8, 0.95, 1.0, 0.8))
