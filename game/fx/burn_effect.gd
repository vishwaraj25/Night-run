extends Node2D
## Fire stuck to an enemy. Attached as a child of whatever the flamethrower is
## cooking, so it moves with the target instead of being a puff left behind in
## the air -- that difference is most of why the flamethrower didn't read as
## connecting with anything.
##
## Refreshed rather than stacked: hitting an already-burning enemy tops the
## timer back up (see attach_to), so a sustained jet holds one steady fire on
## each target rather than piling up a dozen overlapping copies.
##
## It also keeps damaging after the jet moves off, which is what makes fire
## feel different from a gun: you commit a second of flame and then move on.

const GROUP := "burn_effect"

@export var duration: float = 1.1
@export var dps: float = 6.0
@export var body_height: float = 110.0 # how tall the burning silhouette is drawn

var _time_left: float = 0.0
var _anim: float = 0.0
var _tick: float = 0.0
var _target: Node = null

func _ready() -> void:
	add_to_group(GROUP)
	z_index = 20 # over the enemy sprite, under the HUD

func _process(delta: float) -> void:
	_anim += delta
	_time_left -= delta
	queue_redraw()

	# Burn damage, applied in ticks rather than continuously so it can't
	# out-damage the weapon that lit it just by running at a high frame rate.
	_tick += delta
	if _tick >= 0.2:
		_tick = 0.0
		if is_instance_valid(_target) and _target.has_method("take_damage"):
			_target.take_damage(dps * 0.2)

	if _time_left <= 0.0:
		queue_free()

## Light `enemy` on fire, or top up the fire it already has. Returns the
## effect so the caller can tune it.
static func attach_to(enemy: Node2D, height: float) -> Node2D:
	for child in enemy.get_children():
		if child.is_in_group(GROUP):
			child._time_left = child.duration
			return child
	var fx: Node2D = load("res://fx/burn_effect.tscn").instantiate()
	fx.body_height = height
	enemy.add_child(fx)
	fx.position = Vector2(0, -height * 0.5)
	fx._target = enemy
	fx._time_left = fx.duration
	return fx

func _draw() -> void:
	var life: float = clampf(_time_left / duration, 0.0, 1.0)
	var h: float = body_height
	var w: float = h * 0.42

	# A wash of heat over the body, so the enemy itself looks alight rather
	# than having a separate effect floating next to it.
	draw_rect(Rect2(-w * 0.6, -h * 0.5, w * 1.2, h),
		Color(1.0, 0.35, 0.05, 0.20 * life))

	# Tongues rising off it, each on its own phase and dying out as they climb.
	for i in 7:
		var base_x: float = lerpf(-w * 0.5, w * 0.5, float(i) / 6.0)
		var phase: float = _anim * 7.0 + float(i) * 1.9
		var climb: float = h * (0.62 + 0.30 * (0.5 + 0.5 * sin(phase)))
		var sway: float = sin(phase * 1.4) * w * 0.18
		var root := Vector2(base_x, h * 0.5)
		var mid := Vector2(base_x + sway * 0.5, h * 0.5 - climb * 0.55)
		var tip := Vector2(base_x + sway, h * 0.5 - climb)
		var thickness: float = 3.6 + 2.2 * (0.5 + 0.5 * sin(phase * 0.8 + 1.1))
		draw_line(root, mid, Color(1.0, 0.42, 0.05, 0.62 * life), thickness)
		draw_line(mid, tip, Color(1.0, 0.82, 0.32, 0.55 * life), thickness * 0.55)

	# Embers drifting up off the top.
	for k in 4:
		var phase: float = _anim * 2.2 + float(k) * 1.55
		var rise: float = fposmod(phase, 1.0)
		var ex: float = sin(phase * 3.1) * w * 0.5
		var ey: float = h * 0.5 - h * (0.55 + rise * 0.55)
		draw_circle(Vector2(ex, ey), 2.6 * (1.0 - rise), Color(1.0, 0.7, 0.25, (1.0 - rise) * life))
