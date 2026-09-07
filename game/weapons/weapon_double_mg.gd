extends "res://weapons/weapon_base.gd"
## Twin-barrel machine gun: fires two bullets side by side (offset
## perpendicular to the aim direction) per shot instead of one — more
## burst damage per trigger pull than the standard mg, at a similar
## fire rate rather than true single-target DPS doubling.

@export var barrel_offset: float = 5.0

func _ready() -> void:
	weapon_name = "double_mg"
	fire_sound = "shoot_double"

func _spawn_projectile() -> void:
	if projectile_scene == null:
		return
	var perp := Vector2.UP.rotated(global_rotation) * barrel_offset
	for side in [-1.0, 1.0]:
		var proj := projectile_scene.instantiate()
		proj.global_position = global_position + perp * side
		proj.global_rotation = global_rotation
		proj.set("damage", damage)
		get_tree().current_scene.add_child(proj)
