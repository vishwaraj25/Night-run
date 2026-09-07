extends "res://weapons/weapon_base.gd"
## Flamethrower: no projectile, damages everything in a cone in front of
## the gun each tick while held.
##
## It was "not working" mostly because you couldn't tell it was: it drew a
## static orange rectangle that never changed whether you were firing or
## not (nothing ever called queue_redraw), and 4 damage a tick against 30hp
## drones took over a second of contact with zero hit feedback. The cone
## now only appears while actually firing, and hits harder.

const GroundNav = preload("res://enemies/ground_nav.gd")
const BurnEffect = preload("res://fx/burn_effect.gd")

@export var range_px: float = 340.0 # was 220 -- shorter than the distance most enemies hold
@export var tick_damage: float = 7.0
@export var tick_rate: float = 0.1
@export var cone_half_angle_deg: float = 34.0

var _flame_timer: float = 0.0
var _flame_held: float = 0.0    # how long the trigger has been down, so the jet ramps up
var _anim: float = 0.0          # free-running clock for the flicker

func _ready() -> void:
	weapon_name = "flamethrower"
	fire_rate = tick_rate
	damage = tick_damage

func _process(delta: float) -> void:
	super._process(delta)
	_anim += delta
	if _flame_timer > 0.0:
		_flame_timer = max(0.0, _flame_timer - delta)
		_flame_held = minf(_flame_held + delta, 0.35)
		queue_redraw()
		Audio.loop("flame_loop")
	elif _flame_held > 0.0:
		_flame_held = maxf(0.0, _flame_held - delta * 2.0) # jet dies back quickly
		if _flame_held <= 0.0:
			Audio.stop_loop("flame_loop")
		queue_redraw()

func _spawn_projectile() -> void:
	_flame_timer = 0.12
	queue_redraw()
	var forward := Vector2.RIGHT.rotated(global_rotation)
	var side := Vector2(-forward.y, forward.x)
	var cone_tan := tan(deg_to_rad(cone_half_angle_deg))
	for enemy in get_tree().get_nodes_in_group("enemy"):
		var aim_point: Vector2 = GroundNav.body_centre(enemy)
		var to_enemy: Vector2 = aim_point - global_position
		var along: float = to_enemy.dot(forward)
		# Widening cone with a minimum mouth, so something standing right on
		# top of you and below the barrel still catches fire.
		var spread: float = maxf(along * cone_tan, 90.0)
		if along >= 0.0 and along <= range_px and absf(to_enemy.dot(side)) <= spread:
			enemy.take_damage(damage)
			# Set the target itself alight. A one-shot spark in the air told
			# you the weapon was firing but never which enemies were actually
			# catching it; fire parented to the enemy moves with it, stacks
			# into one steady flame rather than a pile of copies, and keeps
			# burning for a beat after the jet sweeps off.
			BurnEffect.attach_to(enemy, _burn_height(enemy))

func _draw() -> void:
	super._draw() # keep the muzzle flash
	if _flame_held <= 0.0:
		return

	# The old version was one flat translucent triangle that looked identical
	# every frame -- static geometry reads as a UI overlay, not as fire. This
	# builds the jet from three nested cones that each flicker on their own
	# clock, plus tongues of flame licking out past the tip, and ramps the
	# whole thing up over the first third of a second of holding the trigger.
	var ramp: float = clampf(_flame_held / 0.35, 0.25, 1.0)
	var half := deg_to_rad(cone_half_angle_deg)
	var reach: float = range_px * ramp

	# Alphas stay low on the wide outer layers: at 0.30 the outermost cone read
	# as a solid dark slab sitting over the scene rather than as smoke at the
	# edge of a jet. The brightness belongs in the narrow core.
	var layers := [
		{"len": 0.92, "half": 0.72, "color": Color(0.80, 0.20, 0.04, 0.11), "speed": 11.0},
		{"len": 0.82, "half": 0.50, "color": Color(1.00, 0.40, 0.06, 0.28), "speed": 17.0},
		{"len": 0.58, "half": 0.34, "color": Color(1.00, 0.68, 0.15, 0.45), "speed": 23.0},
		{"len": 0.30, "half": 0.17, "color": Color(1.00, 0.95, 0.70, 0.80), "speed": 29.0},
	]
	for i in layers.size():
		var layer: Dictionary = layers[i]
		var flicker: float = 1.0 + sin(_anim * float(layer["speed"]) + float(i) * 1.7) * 0.09
		var l: float = reach * float(layer["len"]) * flicker
		var h: float = half * float(layer["half"])
		var pts := PackedVector2Array([Vector2.ZERO])
		# Sample the arc so the cone's mouth is round like a flame front
		# rather than a straight-edged wedge.
		for step in 9:
			var t: float = -1.0 + 2.0 * float(step) / 8.0
			var wobble: float = 1.0 + sin(_anim * 13.0 + t * 6.0 + float(i)) * 0.08
			pts.append(Vector2(l * wobble, 0).rotated(h * t))
		draw_colored_polygon(pts, layer["color"])

	# Tongues past the flame front, each on its own phase so they lick.
	for k in 7:
		var t: float = -1.0 + 2.0 * float(k) / 6.0
		var phase: float = _anim * 9.0 + float(k) * 2.1
		var len_out: float = reach * (0.92 + 0.18 * sin(phase))
		var tongue := Vector2(len_out, 0).rotated(half * t * 0.8)
		var root := tongue * 0.68
		draw_line(root, tongue, Color(1.0, 0.72, 0.22, 0.35 + 0.3 * sin(phase * 1.3)), 5.0)

	# Nozzle bloom, so the jet clearly starts at the barrel.
	draw_circle(Vector2(6, 0), 9.0 * ramp, Color(1.0, 0.95, 0.75, 0.8))


## How tall to draw the fire on a given enemy, from its collision box -- a
## drone and a sentry bot are wildly different sizes and one fixed height
## would either float over the small ones or swamp them.
func _burn_height(enemy: Node2D) -> float:
	var shape := enemy.get_node_or_null("CollisionShape2D")
	if shape and shape.shape is RectangleShape2D:
		return (shape.shape as RectangleShape2D).size.y
	return 110.0


func _exit_tree() -> void:
	Audio.stop_loop("flame_loop")
