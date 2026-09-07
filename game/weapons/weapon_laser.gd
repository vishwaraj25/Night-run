extends "res://weapons/weapon_base.gd"
## Instant hitscan beam: long range, very tight cone, ticks fast — good for
## picking a single target out of a spread formation rather than an area.
## Same "instant cone check" approach as the flamethrower, just narrow and long
## instead of wide and short.

const ImpactSparkScene = preload("res://fx/impact_spark.tscn")
const GroundNav = preload("res://enemies/ground_nav.gd")

@export var range_px: float = 700.0
@export var tick_damage: float = 3.0
@export var tick_rate: float = 0.05
@export var beam_half_width: float = 70.0 # perpendicular reach of the beam, in pixels

var _beam_timer: float = 0.0
var _beam_length: float = 0.0   # where the beam stopped, so it terminates on the target
var _impact_pulse: float = 0.0
var _anim: float = 0.0          # free-running clock, so the beam boils while held
var _contact: float = 0.0       # ramps up while the beam is actually on something
var _held: float = 0.0          # how long the trigger has been down

func _ready() -> void:
	weapon_name = "laser"
	fire_rate = tick_rate
	damage = tick_damage

func _process(delta: float) -> void:
	super._process(delta)
	_anim += delta
	if _beam_timer > 0.0:
		_beam_timer = max(0.0, _beam_timer - delta)
		_impact_pulse += delta
		_held = minf(_held + delta, 0.3)
		# Contact rises fast and falls fast, so the impact burst appears the
		# instant the beam finds a target and stops the instant it loses one.
		var target: float = 1.0 if _beam_length < range_px else 0.0
		_contact = move_toward(_contact, target, delta * 8.0)
		queue_redraw()
		Audio.loop("laser_loop")
	else:
		_held = maxf(0.0, _held - delta * 4.0)
		_contact = maxf(0.0, _contact - delta * 6.0)
		if _held <= 0.0:
			Audio.stop_loop("laser_loop")
		if _held > 0.0 or _contact > 0.0:
			queue_redraw()

func _spawn_projectile() -> void:
	_beam_timer = 0.06
	queue_redraw()
	var forward := Vector2.RIGHT.rotated(global_rotation)
	var side := Vector2(-forward.y, forward.x)

	# A beam is a line with thickness, not a cone. The angular test this used
	# to do meant anything shorter than the player slipped under it: a bot 43px
	# below the gun sits 10 degrees off at close range, way outside a 3 degree
	# cone, so the beam drew straight over its head and did nothing. Distance
	# from the beam line is both correct and what it looks like on screen.
	var nearest_dist := range_px
	var nearest: Node2D = null
	for enemy in get_tree().get_nodes_in_group("enemy"):
		var aim_point: Vector2 = GroundNav.body_centre(enemy)
		var to_enemy: Vector2 = aim_point - global_position
		var along: float = to_enemy.dot(forward)
		if along < 0.0 or along > range_px:
			continue
		if absf(to_enemy.dot(side)) > beam_half_width:
			continue
		enemy.take_damage(damage)
		if along < nearest_dist:
			nearest_dist = along
			nearest = enemy

	_beam_length = nearest_dist if nearest else range_px
	if nearest and _impact_pulse >= 0.12:
		# One spark per few ticks, not per tick: at a 0.05s tick rate every
		# tick would be 20 sparks stacked in the same spot.
		_impact_pulse = 0.0
		var spark := ImpactSparkScene.instantiate()
		spark.color = Color(1.0, 0.35, 0.35)
		spark.max_radius = 22.0
		get_tree().current_scene.add_child(spark)
		spark.global_position = global_position + forward * nearest_dist

func _draw() -> void:
	super._draw() # keep the muzzle flash
	if _held <= 0.0 and _contact <= 0.0:
		return

	var end := Vector2(_beam_length, 0)
	var ramp: float = clampf(_held / 0.3, 0.35, 1.0)
	# Boil the beam width slightly instead of holding a dead-flat line -- a
	# constant-width bar reads as a UI element, a breathing one reads as
	# something under power.
	var boil: float = 1.0 + sin(_anim * 34.0) * 0.12

	draw_line(Vector2.ZERO, end, Color(1.0, 0.15, 0.15, 0.20 * ramp), 15.0 * boil * ramp)
	draw_line(Vector2.ZERO, end, Color(1.0, 0.28, 0.28, 0.80 * ramp), 6.5 * boil * ramp)
	draw_line(Vector2.ZERO, end, Color(1.0, 0.92, 0.92, 0.95 * ramp), 2.4 * boil * ramp)

	if _contact <= 0.0:
		return

	# --- the contact point. This is what sells "I am burning a hole in you":
	# a hot pool that pulses, a ring of ejecta thrown back along the beam, and
	# a scatter of sparks. Previously the beam just ended in a small dot, which
	# looked the same whether it was hitting an enemy or the far wall.
	var c: float = _contact
	var pulse: float = 0.85 + 0.15 * sin(_anim * 40.0)

	draw_circle(end, 26.0 * c * pulse, Color(1.0, 0.25, 0.15, 0.22 * c))
	draw_circle(end, 13.0 * c * pulse, Color(1.0, 0.55, 0.35, 0.55 * c))
	draw_circle(end, 6.0 * c * pulse, Color(1.0, 0.97, 0.9, 0.95 * c))

	# Ejecta: short streaks flung back toward the shooter, splayed around the
	# beam axis, each on its own phase so the spray keeps moving.
	for i in 9:
		var phase: float = _anim * 15.0 + float(i) * 2.3
		var spread: float = deg_to_rad(120.0 + 55.0 * sin(phase * 0.7))
		var t: float = -1.0 + 2.0 * float(i) / 8.0
		var dir := Vector2.RIGHT.rotated(spread * t)
		var length: float = (14.0 + 12.0 * absf(sin(phase))) * c
		draw_line(end + dir * 4.0, end + dir * length,
			Color(1.0, 0.6, 0.3, (0.55 + 0.35 * sin(phase * 1.7)) * c), 2.2)

	# A faint scorch ring left sitting on the surface.
	draw_arc(end, 18.0 * c, 0.0, TAU, 20, Color(1.0, 0.35, 0.2, 0.35 * c), 2.0, true)


## A weapon can be swapped away mid-beam (the pickup timer runs out, or you
## walk over another crate). Without this the loop keeps playing with nothing
## driving it.
func _exit_tree() -> void:
	Audio.stop_loop("laser_loop")
