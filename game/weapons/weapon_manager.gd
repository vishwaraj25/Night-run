extends Node2D
## Child of the player node. Owns the currently-equipped weapon and auto-fires it.
## Crates call equip(scene) without needing to know what weapons exist —
## that's the whole point of routing pickups through this one interface.
##
## Two aim modes:
## - Continuous (default, what the car uses): the whole node rotates smoothly
##   to face the mouse, and the weapon sits at a fixed local muzzle_offset.
##   Works because the car has no discrete aim poses of its own to match.
## - Discrete (player_cyborg): the sprite only has 3 fixed aim poses
##   (forward/up/down, no in-between angles), so a smoothly-rotating weapon
##   drifts away from the fixed gun art the moment the mouse isn't dead
##   level — that was a real bug (bullets visibly spawning off in space next
##   to the gun). In this mode the node itself never rotates; instead the
##   weapon snaps between 3 measured (position, rotation) pairs, one per
##   zone, using the exact same y-threshold the character controller uses to
##   pick its sprite frame, so the two always agree on which pose is showing.

@export var default_weapon_scene: PackedScene
@export var muzzle_offset: Vector2 = Vector2(24, -6)
@export var aim_clamp_degrees: float = 85.0   # can sweep almost straight up/down, not behind

@export var discrete_aim_zones: bool = false
@export var muzzle_offset_up: Vector2 = Vector2.ZERO
@export var muzzle_offset_down: Vector2 = Vector2.ZERO
@export var aim_up_angle_degrees: float = -25.0
@export var aim_down_angle_degrees: float = 20.0
const AIM_ZONE_Y_THRESHOLD := 0.4 # must match player_cyborg_controller.gd's _aim_column

var _current_weapon: Node = null
var _weapon_time: float = 0.0     # seconds left on a timed pickup; 0 = permanent
var _weapon_duration: float = 0.0 # what it started at, for the HUD's fraction

func _ready() -> void:
	if default_weapon_scene:
		equip(default_weapon_scene)

func _process(delta: float) -> void:
	# A dead host does not shoot. This runs on its own _process, so it used to
	# keep firing straight through the death animation for as long as the fire
	# button stayed down -- gunshots, muzzle flashes and a sustained laser loop
	# over a corpse. The controller early-returns when dead; this has to check
	# the same thing rather than assume it was told.
	# The sustained weapons stop on their own once fire() stops arriving (their
	# beam timers decay and close the audio loop), so returning here is enough.
	var host := get_parent()
	if host and host.has_method("is_dead") and host.is_dead():
		return

	_tick_weapon_timer(delta)
	_update_aim()
	if Input.is_action_pressed("fire") and _current_weapon and _current_weapon.has_method("fire"):
		_current_weapon.fire()

func _update_aim() -> void:
	if not Input.is_action_pressed("fire"):
		return # matches the character's own aim gating -- no aim without firing

	# Ask the character where it's aiming when it can answer (player_cyborg),
	# so the gun and the drawn aim pose come from one computation instead of
	# two copies of the mouse math that can drift apart. The car has no such
	# method and keeps the mouse path below.
	var host := get_parent()
	var aim: Vector2 = host.get_aim_direction() if host and host.has_method("get_aim_direction") else Vector2.ZERO
	if aim == Vector2.ZERO:
		var to_mouse := get_global_mouse_position() - global_position
		if to_mouse.length() < 1.0:
			return
		aim = to_mouse.normalized()

	if discrete_aim_zones:
		var dir := aim
		var base_offset: Vector2
		var base_angle_deg: float
		if dir.y < -AIM_ZONE_Y_THRESHOLD:
			base_offset = muzzle_offset_up
			base_angle_deg = aim_up_angle_degrees
		elif dir.y > AIM_ZONE_Y_THRESHOLD:
			base_offset = muzzle_offset_down
			base_angle_deg = aim_down_angle_degrees
		else:
			base_offset = muzzle_offset
			base_angle_deg = 0.0

		# All 3 measured poses/offsets are for facing right. When aiming left
		# (matches the same dir.x < 0 check player_cyborg_controller.gd uses
		# for its own flip_h), mirror both the position and the launch angle
		# across the vertical axis -- this was the actual bug: bullets always
		# fired rightward regardless of facing, because this branch never
		# looked at dir.x at all.
		if dir.x < 0.0:
			_current_weapon.position = Vector2(-base_offset.x, base_offset.y)
			_current_weapon.rotation = PI - deg_to_rad(base_angle_deg)
		else:
			_current_weapon.position = base_offset
			_current_weapon.rotation = deg_to_rad(base_angle_deg)
	else:
		# Aim in world space (not relative to the car's own tilt on a slope)
		# so the gun always points where the mouse is on screen, consistently.
		var clamp_rad := deg_to_rad(aim_clamp_degrees)
		global_rotation = clamp(aim.angle(), -clamp_rad, clamp_rad)

## Picked-up weapons are on a timer. `duration` of 0 means permanent, which is
## what the starting weapon gets; anything a crate hands you runs out and drops
## you back to the default. The HUD shows the remaining time, so losing the
## laser is something you can see coming and plan around rather than a surprise
## mid-fight.
func equip(weapon_scene: PackedScene, duration: float = 0.0) -> void:
	if _current_weapon:
		_current_weapon.queue_free()

	_current_weapon = weapon_scene.instantiate()
	add_child(_current_weapon)
	_current_weapon.position = muzzle_offset

	_weapon_time = duration
	_weapon_duration = duration
	var weapon_name: String = _current_weapon.get("weapon_name")
	EventBus.weapon_changed.emit(weapon_name)
	EventBus.weapon_timer_changed.emit(_weapon_time, _weapon_duration)

func _tick_weapon_timer(delta: float) -> void:
	if _weapon_duration <= 0.0:
		return
	_weapon_time = maxf(0.0, _weapon_time - delta)
	EventBus.weapon_timer_changed.emit(_weapon_time, _weapon_duration)
	if _weapon_time <= 0.0 and default_weapon_scene:
		equip(default_weapon_scene) # back to the starting gun, permanently
