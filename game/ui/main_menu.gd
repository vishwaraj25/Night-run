extends Control
## Main menu.
##
## The words PLAY / CONTROLS / QUIT are painted into the background art, not
## drawn as labels, so the buttons here are invisible hitboxes that have to sit
## exactly on top of that painted text.
##
## They used to be placed at fixed pixel offsets authored against a 960x540
## view. That only lines up at one aspect ratio. The background is drawn with
## KEEP_ASPECT_COVERED, so on any other shape of screen it scales and crops by
## a different amount and the painted text slides out from under the hitboxes
## -- on a phone, far enough that tapping the word PLAY hit nothing and the
## live button sat somewhere off in the artwork. That is the "menu is out of
## bounds" report.
##
## So the rects are stored where they are actually stable: as fractions of the
## background image itself. At runtime they are mapped through the same cover
## transform the TextureRect uses, which puts them back on the text at every
## size and aspect ratio, and scales them up on a big phone screen for free.

const BG_SIZE := Vector2(1920.0, 1279.0) ## must match assets/main_menu_bg.png

## Fractions of the background image: x, y, width, height. Measured off the
## artwork itself by finding the near-white glyph pixels of each word (the
## city neon behind them is saturated, the lettering is not), then padded a
## little for thumbs. Measured rather than converted from the old offsets
## because those were themselves short on the right: the original PLAY box
## stopped 57px before the end of the Y, so the last letter was never
## clickable even at the resolution it was authored for.
const BUTTON_RECTS := {
	"PlayButton":     Rect2(0.5995, 0.3182, 0.1266, 0.0915),
	"ControlsButton": Rect2(0.5365, 0.4535, 0.2536, 0.0923),
	"QuitButton":     Rect2(0.6047, 0.5887, 0.1104, 0.0923),
}

const PANEL_SIZE := Vector2(720.0, 360.0)

@onready var play_button: Button = $PlayButton
@onready var controls_button: Button = $ControlsButton
@onready var quit_button: Button = $QuitButton
@onready var controls_panel: Panel = $ControlsPanel
@onready var close_button: Button = $ControlsPanel/CloseButton

func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)
	controls_button.pressed.connect(_on_controls_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	close_button.pressed.connect(_on_close_controls_pressed)

	# Nothing to quit to in a browser tab, and the call is a no-op there, so
	# the hitbox would be a word that does nothing when tapped.
	if OS.has_feature("web") or OS.has_feature("mobile"):
		quit_button.disabled = true

	$ControlsPanel/List.text = _controls_text()

	get_viewport().size_changed.connect(_relayout)
	_relayout()

func _relayout() -> void:
	var view := get_viewport_rect().size
	if view.x <= 0.0 or view.y <= 0.0:
		return

	# The same transform TextureRect applies for STRETCH_KEEP_ASPECT_COVERED:
	# scale to cover, then centre and let the overflow crop.
	var cover: float = maxf(view.x / BG_SIZE.x, view.y / BG_SIZE.y)
	var origin: Vector2 = (view - BG_SIZE * cover) * 0.5

	for node_name in BUTTON_RECTS:
		var frac: Rect2 = BUTTON_RECTS[node_name]
		var button: Control = get_node_or_null(NodePath(node_name))
		if not button:
			continue
		button.position = origin + frac.position * BG_SIZE * cover
		button.size = frac.size * BG_SIZE * cover

	# The controls panel is plain UI rather than painted art, so it just needs
	# to be centred, and shrunk if the view is too small to hold it.
	var fit: float = minf(1.0, minf(view.x / (PANEL_SIZE.x + 40.0), view.y / (PANEL_SIZE.y + 40.0)))
	controls_panel.scale = Vector2(fit, fit)
	controls_panel.size = PANEL_SIZE
	controls_panel.position = (view - PANEL_SIZE * fit) * 0.5

## Written from the input map rather than from memory: aiming has not been
## mouse-driven since the Contra scheme went in, and the old panel still told
## players it was.
func _controls_text() -> String:
	if DisplayServer.is_touchscreen_available() or OS.has_feature("mobile"):
		return """Move - the < and > pads
Aim up - the ^ pad while firing
Aim down - the v pad while firing, in the air
Crouch - the v pad on the ground
Jump - JUMP (tap twice for a double jump)
Fire - hold FIRE
Shield - hold SHIELD. Time it and you deflect the shot back"""
	return """Move - A / D or Left / Right
Aim up - hold Up while firing
Aim down - hold Down while firing, in the air
Crouch - S or Down on the ground
Jump - Space (tap twice for a double jump)
Fire - hold Ctrl or the left mouse button
Shield - hold Shift. Time it and you deflect the shot back
Pause - Escape or P      Mute - M"""

func _on_play_pressed() -> void:
	Audio.play("menu_click")
	Telemetry.log_event("menu_click", {"button": "play"})
	get_tree().change_scene_to_file("res://world/level.tscn")

func _on_controls_pressed() -> void:
	Audio.play("menu_click")
	Telemetry.log_event("menu_click", {"button": "controls"})
	controls_panel.visible = true

func _on_close_controls_pressed() -> void:
	Audio.play("menu_click")
	Telemetry.log_event("menu_click", {"button": "close_controls"})
	controls_panel.visible = false

func _on_quit_pressed() -> void:
	Audio.play("menu_click")
	Telemetry.log_event("menu_click", {"button": "quit"})
	get_tree().quit()
