extends Node2D
## Short-lived burst drawn where a bullet actually landed. Cheap, but it's
## the difference between "did that hit?" and visible confirmation on every
## single shot -- previously bullets just vanished on contact.

@export var lifetime: float = 0.13
@export var max_radius: float = 16.0
@export var color: Color = Color(1.0, 0.92, 0.45)

var _age: float = 0.0

func _process(delta: float) -> void:
	_age += delta
	queue_redraw()
	if _age >= lifetime:
		queue_free()

func _draw() -> void:
	var t: float = clampf(_age / lifetime, 0.0, 1.0)
	var radius: float = lerpf(3.0, max_radius, t)
	var fade: Color = color
	fade.a = 1.0 - t
	draw_circle(Vector2.ZERO, radius, fade)
	# a brighter core that shrinks as the outer ring expands
	var core: Color = Color(1, 1, 1, (1.0 - t) * 0.9)
	draw_circle(Vector2.ZERO, lerpf(3.0, 1.0, t) * 2.0, core)
