extends Area2D
## Weapon and support pickup. Real crate art now (item_crate_spritesheet.png,
## 4 rows x 4 cols): the row picks the item, the column is the animation --
## col 0 closed, col 1 lid lit, col 2 open with the contents rising out. It
## breathes between closed and lit so it reads as live from across the screen,
## and pops open on the frame you take it.
##
## The name plate under it stays. A crate icon tells you it's a pickup; the
## label is what tells you it's a LASER and not a flamethrower, and that was
## the whole point of adding it.
##
## Anything with no crate art (the jetpack) falls back to the drawn capsule
## this scene used to be entirely.

const SHEET_COLS := 4
const SHEET_ROWS := 4
const COL_CLOSED := 0
const COL_LIT := 1
const COL_OPEN := 2

## row in the sheet, plus the label and colour used by the fallback capsule
const ITEMS := {
	"machine_gun":  {"row": 0, "letter": "M", "label": "MACHINE GUN",  "color": Color(1.00, 0.85, 0.20)},
	"double_mg":    {"row": 0, "letter": "D", "label": "DOUBLE MG",    "color": Color(1.00, 0.55, 0.15)},
	"laser":        {"row": 1, "letter": "L", "label": "LASER",        "color": Color(0.30, 0.90, 1.00)},
	"flamethrower": {"row": 2, "letter": "F", "label": "FLAMETHROWER", "color": Color(1.00, 0.32, 0.20)},
	"medkit":       {"row": 3, "letter": "+", "label": "MEDKIT",       "color": Color(0.35, 1.00, 0.45)},
	"jetpack":      {"row": -1, "letter": "J", "label": "JETPACK 10s", "color": Color(0.55, 0.70, 1.00)},
}

@export var item_name: String = "flamethrower"
@export var weapon_scene: PackedScene
@export var heal_amount: float = 35.0      # used when item_name is "medkit"
@export var jetpack_seconds: float = 10.0  # used when item_name is "jetpack"
@export var weapon_seconds: float = 25.0   # how long a picked-up weapon lasts before reverting
@export var bob_amplitude: float = 6.0
@export var bob_speed: float = 2.5

var _time: float = 0.0
var _base_y: float
var _base_set: bool = false
var _row: int = -1

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	# NOT _base_y here. _ready runs on add_child(), so anything positioned
	# after being added -- the boss's phase drops, for one -- would have its
	# bob anchored to y=0 and get yanked back into the sky on the next frame.
	# Captured on the first _process instead, once the position has settled.
	_row = int(ITEMS.get(item_name, {}).get("row", -1))
	sprite.visible = _row >= 0
	if _row >= 0:
		sprite.frame = _row * SHEET_COLS + COL_CLOSED
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	if not _base_set:
		_base_y = position.y
		_base_set = true
	_time += delta
	position.y = _base_y + sin(_time * bob_speed) * bob_amplitude
	if _row >= 0:
		# Slow pulse between closed and lit, so an unopened crate is obviously
		# still there to be taken rather than looking like scenery.
		var lit: bool = fmod(_time, 1.6) > 0.8
		sprite.frame = _row * SHEET_COLS + (COL_LIT if lit else COL_CLOSED)
	else:
		queue_redraw()

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	EventBus.item_collected.emit(item_name)
	Audio.play("pickup")
	match item_name:
		"medkit":
			if body.has_method("heal"):
				body.heal(heal_amount)
		"jetpack":
			if body.has_method("grant_jetpack"):
				body.grant_jetpack(jetpack_seconds)
		_:
			var weapon_manager := body.get_node_or_null("WeaponManager")
			if weapon_manager and weapon_scene:
				weapon_manager.equip(weapon_scene, weapon_seconds)

	# Show the open frame for a beat instead of vanishing mid-air, so taking a
	# pickup has a visible result at the crate as well as on the HUD.
	if _row >= 0:
		sprite.frame = _row * SHEET_COLS + COL_OPEN
		set_deferred("monitoring", false)
		var tw := create_tween()
		tw.tween_interval(0.18)
		tw.tween_property(self, "modulate:a", 0.0, 0.22)
		tw.tween_callback(queue_free)
	else:
		queue_free()

func _draw() -> void:
	var info: Dictionary = ITEMS.get(item_name,
		{"letter": "?", "label": item_name.replace("_", " ").to_upper(), "color": Color(0.8, 0.8, 0.8)})
	var core: Color = info["color"]
	var shell := Color(0.08, 0.08, 0.11)

	# Name plate, drawn twice (dark then light) so it holds up over both the
	# bright neon signs and the dark rooftops. Every crate gets one -- the art
	# says "pickup", the label says which pickup.
	var plate_font := ThemeDB.fallback_font
	var name_text: String = info["label"]
	var name_dims := plate_font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
	var name_pos := Vector2(-name_dims.x * 0.5, 34.0)
	draw_string(plate_font, name_pos + Vector2(1, 1), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		13, Color(0, 0, 0, 0.8))
	draw_string(plate_font, name_pos, name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, core)

	# Below here is the fallback capsule, for items with no crate art yet.
	if _row >= 0:
		return

	draw_circle(Vector2(-14, 0), 15.0, shell)
	draw_circle(Vector2(14, 0), 15.0, shell)
	draw_rect(Rect2(-14, -15, 28, 30), shell)
	draw_circle(Vector2(-14, 0), 11.0, core)
	draw_circle(Vector2(14, 0), 11.0, core)
	draw_rect(Rect2(-14, -11, 28, 22), core)

	var font := ThemeDB.fallback_font
	var text: String = info["letter"]
	var dims := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
	draw_string(font, Vector2(-dims.x * 0.5, dims.y * 0.34), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, shell)
