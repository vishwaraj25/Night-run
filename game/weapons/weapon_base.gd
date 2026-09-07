class_name WeaponBase
extends Node2D
## Base weapon behavior. A weapon is a child node under WeaponManager that
## knows how to fire and what it looks like as a placeholder rectangle.
## New weapons (flamethrower, shield) extend this and override fire()/_draw().

@export var weapon_name: String = "machine_gun"
@export var fire_rate: float = 0.25       # seconds between shots
@export var damage: float = 10.0
@export var projectile_scene: PackedScene
@export var fire_sound: String = "shoot_mg"

const MUZZLE_FLASH_TIME := 0.05

var _cooldown: float = 0.0
var _muzzle_flash: float = 0.0

func _process(delta: float) -> void:
	_cooldown = max(0.0, _cooldown - delta)
	if _muzzle_flash > 0.0:
		_muzzle_flash = max(0.0, _muzzle_flash - delta)
		queue_redraw()

func can_fire() -> bool:
	return _cooldown <= 0.0

func fire() -> void:
	if not can_fire():
		return
	_cooldown = fire_rate
	_spawn_projectile()

func _spawn_projectile() -> void:
	if projectile_scene == null:
		return
	var proj := projectile_scene.instantiate()
	# Position/rotation MUST be set before add_child(): add_child() runs the
	# projectile's _ready() immediately, so anything that reads its own
	# rotation there (to compute a launch direction, say) would otherwise
	# always see the default (0 = rightward) instead of the real aim.
	proj.global_position = global_position
	proj.global_rotation = global_rotation
	proj.set("damage", damage)
	get_tree().current_scene.add_child(proj)
	Audio.play(fire_sound)
	_muzzle_flash = MUZZLE_FLASH_TIME
	queue_redraw()

# Safe to draw at this node again now that discrete_aim_zones keeps the weapon
# transform matched to the gun in the sprite -- back when the weapon rotated
# continuously against 3 fixed sprite poses, anything drawn here visibly
# floated away from the gun.
func _draw() -> void:
	if _muzzle_flash <= 0.0:
		return
	var t: float = _muzzle_flash / MUZZLE_FLASH_TIME
	var length: float = 26.0 * t
	var half: float = 7.0 * t
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, -half), Vector2(length, 0), Vector2(0, half),
	]), Color(1.0, 0.85, 0.4, 0.95))
	draw_circle(Vector2.ZERO, 5.0 * t, Color(1, 1, 1, 0.9))

# No _draw() here anymore -- this used to render a yellow aim-indicator line
# at the weapon node's own (continuously-rotating) position, which made sense
# when the car had no discrete aim poses of its own. Now that player_cyborg
# has real drawn aim frames (forward/up/down), the two disagree: the weapon
# node keeps rotating smoothly with the raw mouse angle while the sprite only
# snaps between 3 fixed poses, so the indicator visibly drifted away from the
# gun in the art. The sprite itself communicates aim direction now.
