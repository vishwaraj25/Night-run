extends Area2D
## A respawn point. Walk through one and dying sends you back here instead of
## to the main menu, so a level this long doesn't have to be replayed from the
## street every time.
##
## Placed only on flat, quiet ground with no encounter within a screen of it --
## respawning into a firefight is worse than restarting.
##
## Drawn in code: a dark pylon that lights cyan and raises a beam once armed,
## so an armed checkpoint is obvious from a distance and you know the progress
## is banked.

@export var respawn_offset: Vector2 = Vector2(0, -20) ## where the player reappears, relative to this

var armed: bool = false
var _time: float = 0.0

func _ready() -> void:
	add_to_group("checkpoint")
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	_time += delta
	if armed:
		queue_redraw() # only the lit state animates

func _on_body_entered(body: Node) -> void:
	if armed or not body.is_in_group("player"):
		return
	armed = true
	Audio.play("checkpoint")
	EventBus.checkpoint_reached.emit(global_position + respawn_offset)
	queue_redraw()

func _draw() -> void:
	var body_col := Color(0.16, 0.18, 0.24)
	var lit: Color = Color(0.35, 0.9, 1.0) if armed else Color(0.30, 0.34, 0.42)

	# Post and base.
	draw_rect(Rect2(-9, -78, 18, 78), body_col)
	draw_rect(Rect2(-26, -10, 52, 12), body_col)
	draw_rect(Rect2(-6, -74, 12, 66), lit)

	# Lamp.
	draw_circle(Vector2(0, -86), 11.0, body_col)
	draw_circle(Vector2(0, -86), 7.0, lit)

	if not armed:
		return

	# Beam and halo once banked, pulsing so it reads as live.
	var pulse: float = 0.5 + 0.5 * sin(_time * 3.0)
	draw_circle(Vector2(0, -86), 15.0 + 5.0 * pulse, Color(lit.r, lit.g, lit.b, 0.22))
	draw_rect(Rect2(-5, -300, 10, 214), Color(lit.r, lit.g, lit.b, 0.10 + 0.10 * pulse))
	var font := ThemeDB.fallback_font
	var text := "CHECKPOINT"
	var dims := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
	draw_string(font, Vector2(-dims.x * 0.5 + 1, -104), text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		12, Color(0, 0, 0, 0.8))
	draw_string(font, Vector2(-dims.x * 0.5, -105), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, lit)
