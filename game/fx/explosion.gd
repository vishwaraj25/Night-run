extends Node2D
## Death explosion. Everything that dies now goes out with one of these
## instead of just vanishing mid-frame, which read as a bug more than a kill.
##
## Drawn in code rather than from a sheet: a shockwave ring, an expanding
## fireball that cools white -> yellow -> orange -> red as it grows, and a
## handful of sparks thrown outward. Scale it with `radius` per enemy so a
## drone and the boss don't blow up at the same size.

@export var lifetime: float = 0.45
@export var radius: float = 70.0
@export var spark_count: int = 10

var _age: float = 0.0
var _sparks: Array[Vector2] = []   # unit direction per spark
var _spark_len: Array[float] = []  # how far along the radius each one throws

func _ready() -> void:
	z_index = 50 # in front of the corpse it came from
	for i in spark_count:
		var a: float = TAU * (float(i) + randf() * 0.6) / float(spark_count)
		_sparks.append(Vector2(cos(a), sin(a)))
		_spark_len.append(randf_range(0.7, 1.5))

func _process(delta: float) -> void:
	_age += delta
	queue_redraw()
	if _age >= lifetime:
		queue_free()

func _draw() -> void:
	var t: float = clampf(_age / lifetime, 0.0, 1.0)
	var ease_out: float = 1.0 - pow(1.0 - t, 3.0) # fast punch, slow settle

	# Shockwave: a thin ring that outruns the fireball and fades early.
	if t < 0.55:
		var ring_t: float = t / 0.55
		draw_arc(Vector2.ZERO, radius * (0.3 + ring_t * 1.25), 0.0, TAU, 32,
			Color(1.0, 0.85, 0.6, (1.0 - ring_t) * 0.7), 3.0, true)

	# Fireball, cooling as it expands.
	var fire: Color = Color(1.0, 0.98, 0.85).lerp(Color(0.85, 0.18, 0.08), ease_out)
	fire.a = 1.0 - ease_out
	draw_circle(Vector2.ZERO, radius * (0.25 + ease_out * 0.85), fire)

	# White-hot core, gone by the time the fireball is halfway out.
	if t < 0.4:
		draw_circle(Vector2.ZERO, radius * 0.42 * (1.0 - t / 0.4), Color(1, 1, 1, 0.95))

	# Thrown sparks.
	for i in _sparks.size():
		var dir: Vector2 = _sparks[i]
		var dist: float = radius * _spark_len[i] * ease_out
		var tail: Vector2 = dir * dist
		var head: Vector2 = dir * maxf(dist - radius * 0.22, 0.0)
		draw_line(head, tail, Color(1.0, 0.75, 0.35, 1.0 - ease_out), 2.5)

## One-line spawn helper so every death site doesn't repeat the same four
## lines of instantiate/position/add_child.
static func spawn(context: Node, at: Vector2, r: float = 70.0) -> void:
	# Radius doubles as "how big did this sound": the mech's 260 gets the long
	# one, a drone's 70 gets the short one.
	context.get_node("/root/Audio").play("explosion_big" if r >= 150.0 else "explosion")
	var fx: Node2D = load("res://fx/explosion.tscn").instantiate()
	fx.radius = r
	context.get_tree().current_scene.add_child(fx)
	fx.global_position = at
