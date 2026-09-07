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
## the project stretches with "expand" -- a 20:9 phone gets a wider view than a
## 16:9 one, and the pads have to follow the real edges.

const PAD_RADIUS := 52.0
const PAUSE_RADIUS := 30.0
const EDGE_PAD := 30.0
## Cap on any safe-area inset, as a fraction of the view. A notch or a gesture
## bar is a small sliver; a reading bigger than this is a bad number, not a
## huge notch, and gets ignored. See _safe_insets for why that happens.
const MAX_INSET_FRACTION := 0.12

## Bottom corners, thumbs-first: movement left, actions right. Fire sits
## nearest the right thumb's rest position, with jump beside it and shield
## above -- the perfect-deflect window is 0.2s, so shield cannot be behind an
## awkward reach either.
const LAYOUT := [
	{"action": "move_backward", "label": "<",  "corner": "left",  "col": 0, "row": 0},
	{"action": "move_forward",  "label": ">",  "corner": "left",  "col": 1, "row": 0},
	{"action": "lane_up",       "label": "^",  "corner": "left",  "col": 1, "row": 1},
	{"action": "crouch",        "label": "v",  "corner": "left",  "col": 0, "row": 1},
	{"action": "fire",          "label": "FIRE",   "corner": "right", "col": 0, "row": 0},
	{"action": "jump",          "label": "JUMP",   "corner": "right", "col": 1, "row": 0},
	{"action": "shield",        "label": "SHIELD", "corner": "right", "col": 0, "row": 1},
	# Top-right, away from both thumb clusters and clear of the HUD in the
	# opposite corner. Without it a phone has no way to pause or to mute: both
	# were keyboard-only, on a build that ships as a link people open anywhere.
	{"action": "pause",         "label": "II", "corner": "right", "col": 0, "row": 0, "top": true},
]

@export var force_visible: bool = false ## turn on to lay the pads out on desktop

var _buttons: Array = []
var _painter: Node2D

func _ready() -> void:
	layer = 20 # above the HUD
	if not force_visible and not _is_touch_device():
		queue_free()
		return

	# The player checks for this group to decide that there is no mouse to aim
	# with. Without that, a tap on a pad arrives as an emulated mouse motion
	# and the character aims at the pad instead of where it is facing.
	add_to_group("touch_controls")

	_painter = Node2D.new()
	_painter.draw.connect(_draw_pads)
	add_child(_painter)

	for spec in LAYOUT:
		var b := TouchScreenButton.new()
		b.action = spec["action"]
		var shape := CircleShape2D.new()
		shape.radius = _radius_for(spec)
		b.shape = shape
		b.visibility_mode = TouchScreenButton.VISIBILITY_ALWAYS
		add_child(b)
		_buttons.append({"node": b, "spec": spec})

	get_viewport().size_changed.connect(_relayout)
	_relayout()

## A pad that goes away mid-press never sends its own release, and the action
## stays down forever -- the character runs off on its own with nothing held.
## Scene changes (dying to the menu, finishing the boss) do exactly this, with
## a thumb still on the pad.
func _exit_tree() -> void:
	if is_in_group("touch_controls"):
		InputGuard.release_all()

## Touch pads on a desktop build would be dead weight over the play area, and
## a phone with a keyboard attached is not a case worth designing around.
func _is_touch_device() -> bool:
	return DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")

## Left, right and bottom insets in viewport units, so the pads clear a notch,
## a punch-hole or a gesture bar.
##
## Deliberately defensive, because the obvious version of this was the bug.
## It divided the safe area by DisplayServer.screen_get_size(), which on the
## web build is a different rectangle in a different coordinate space: the
## browser reports the whole device screen while the safe area describes the
## canvas. On a phone that produced a bottom inset of a large fraction of the
## view height and threw the pads up into the middle of the screen, nowhere
## near the thumbs and on top of the play area.
func _safe_insets(view_size: Vector2) -> Vector3:
	var win := Vector2(DisplayServer.window_get_size())
	var safe := DisplayServer.get_display_safe_area()
	if win.x <= 0.0 or win.y <= 0.0 or safe.size.x <= 0 or safe.size.y <= 0:
		return Vector3.ZERO
	# If the "safe area" does not fit inside the window it claims to describe,
	# the two are not in the same units. Trust neither.
	if float(safe.size.x) > win.x or float(safe.size.y) > win.y:
		return Vector3.ZERO

	var l: float = maxf(0.0, float(safe.position.x)) / win.x * view_size.x
	var r: float = maxf(0.0, win.x - float(safe.end.x)) / win.x * view_size.x
	var b: float = maxf(0.0, win.y - float(safe.end.y)) / win.y * view_size.y
	var cap_x := view_size.x * MAX_INSET_FRACTION
	var cap_y := view_size.y * MAX_INSET_FRACTION
	return Vector3(minf(l, cap_x), minf(r, cap_x), minf(b, cap_y))

func _relayout() -> void:
	var size := get_viewport().get_visible_rect().size
	var inset := _safe_insets(size)

	var step := PAD_RADIUS * 2.25
	for entry in _buttons:
		var spec: Dictionary = entry["spec"]
		var col: float = float(spec["col"])
		var row: float = float(spec["row"])
		var rad: float = _radius_for(spec)
		var x: float
		if spec["corner"] == "left":
			x = EDGE_PAD + inset.x + rad + col * step
		else:
			x = size.x - EDGE_PAD - inset.y - rad - col * step
		var y: float
		if spec.get("top", false):
			y = EDGE_PAD + rad + row * step
		else:
			y = size.y - EDGE_PAD - inset.z - rad - row * step
		# TouchScreenButton's shape is centred on its position.
		entry["node"].position = Vector2(x, y)
	if _painter:
		_painter.queue_redraw()

## Pause is a tap, not something held under a thumb during play, so it is
## smaller and sits out of the way rather than competing for corner space.
func _radius_for(spec: Dictionary) -> float:
	return PAUSE_RADIUS if spec["action"] == "pause" else PAD_RADIUS

func _draw_pads() -> void:
	var font := ThemeDB.fallback_font
	for entry in _buttons:
		var pos: Vector2 = entry["node"].position
		var label: String = entry["spec"]["label"]
		var rad: float = _radius_for(entry["spec"])
		# Deliberately low contrast: these sit over the play area for the whole
		# game, so they have to be findable by thumb without competing with the
		# enemies for attention.
		_painter.draw_circle(pos, rad, Color(0.05, 0.06, 0.09, 0.38))
		_painter.draw_arc(pos, rad, 0.0, TAU, 28, Color(0.45, 0.85, 1.0, 0.55), 2.0, true)
		var fs := 15 if label.length() > 2 else 24
		var dims := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		_painter.draw_string(font, pos + Vector2(-dims.x * 0.5, dims.y * 0.32), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.8, 0.95, 1.0, 0.8))
