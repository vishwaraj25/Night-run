extends Node2D
## Two emitter sprites (placed as this node's own position and
## `far_offset`) connected by a beam that cycles on/off. The beam is drawn
## procedurally (matching the plain-rect style projectile_base.gd/
## weapon_base.gd already use here) instead of a baked-in sprite, so a
## single scene works at whatever gap the level designer places it at —
## the source art only showed one fixed gap, which would've meant a
## separate asset per distance.
##
## Indestructible — Traps.png never drew a "destroyed" pylon/wall frame for
## this one, unlike the turret/bot.

@export var far_offset: Vector2 = Vector2(400, 0) # position of the second emitter, relative to this node
@export var beam_height_offset: float = 0.0 # vertical offset so the beam lines up with the emitter sprites' actual glow -- differs per skin since each texture's glow sits at a different height within its own image
@export var beam_on_time: float = 1.2
@export var beam_off_time: float = 1.6
@export var beam_width: float = 6.0
@export var beam_damage: float = 15.0
@export var damage_tick_interval: float = 0.3

var _beam_on: bool = false
var _timer: float = 0.0
var _damage_tick_timer: float = 0.0

@onready var area: Area2D = $BeamArea
@onready var collider: CollisionShape2D = $BeamArea/CollisionShape2D

func _ready() -> void:
	_timer = beam_off_time
	_update_collider()
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

func _beam_start() -> Vector2:
	return Vector2(0, beam_height_offset)

func _beam_end() -> Vector2:
	return far_offset + Vector2(0, beam_height_offset)

func _update_collider() -> void:
	var span: Vector2 = _beam_end() - _beam_start()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(span.length(), beam_width)
	collider.shape = shape
	collider.position = _beam_start() + span * 0.5
	collider.rotation = span.angle()

func _draw() -> void:
	if not _beam_on:
		return
	var start: Vector2 = _beam_start()
	var end: Vector2 = _beam_end()
	var span: Vector2 = end - start
	var perp := Vector2(-span.y, span.x).normalized() * (beam_width * 0.5)
	draw_colored_polygon(PackedVector2Array([start - perp, end - perp, end + perp, start + perp]), Color(1.0, 0.25, 0.3, 0.95))
	draw_colored_polygon(PackedVector2Array([
		start - perp * 0.3, end - perp * 0.3, end + perp * 0.3, start + perp * 0.3
	]), Color(1.0, 0.9, 0.85, 1.0))
