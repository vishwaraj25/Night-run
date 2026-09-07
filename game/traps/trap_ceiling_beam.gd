extends Node2D
## Single emitter (the ceiling disc) firing a periodic beam straight down.
## Same on/off-cycle-plus-procedural-beam approach as trap_laser_gate.gd,
## just one-ended instead of two, and vertical instead of whatever angle
## far_offset happens to be.

@export var beam_length: float = 400.0
@export var beam_on_time: float = 0.8
@export var beam_off_time: float = 1.8
@export var beam_width: float = 8.0
@export var beam_damage: float = 15.0
@export var damage_tick_interval: float = 0.3

var _beam_on: bool = false
var _timer: float = 0.0
var _damage_tick_timer: float = 0.0

@onready var area: Area2D = $BeamArea
@onready var collider: CollisionShape2D = $BeamArea/CollisionShape2D

func _ready() -> void:
	_timer = beam_off_time
	var shape := RectangleShape2D.new()
	shape.size = Vector2(beam_width, beam_length)
	collider.shape = shape
	collider.position = Vector2(0, beam_length * 0.5)
	area.monitoring = false

func _physics_process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_beam_on = not _beam_on
		_timer = beam_on_time if _beam_on else beam_off_time
		area.monitoring = _beam_on
		queue_redraw()

	if _beam_on:
		_damage_tick_timer -= delta
		if _damage_tick_timer <= 0.0:
			_damage_tick_timer = damage_tick_interval
			for body in area.get_overlapping_bodies():
				if body.is_in_group("player") and body.has_method("take_damage"):
					body.take_damage(beam_damage, self)

func _draw() -> void:
	if not _beam_on:
		return
	var half := beam_width * 0.5
	draw_colored_polygon(PackedVector2Array([
		Vector2(-half, 0), Vector2(half, 0), Vector2(half, beam_length), Vector2(-half, beam_length)
	]), Color(1.0, 0.25, 0.3, 0.95))
	var core := beam_width * 0.18
	draw_colored_polygon(PackedVector2Array([
		Vector2(-core, 0), Vector2(core, 0), Vector2(core, beam_length), Vector2(-core, beam_length)
	]), Color(1.0, 0.9, 0.85, 1.0))
