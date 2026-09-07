extends "res://enemies/enemy_base.gd"
## Airborne enemy (plane/drone) that weaves up and down as it approaches
## instead of driving the road — spawned in squadron formations by
## EnemySpawner, at heights the ground drones never occupy. Also fires
## back at the player, so a squadron is something to shoot AND dodge.
##
## Sprite sheet: enemy_flyer_spritesheet.png, 8 cols x 5 rows, verified
## frame-by-frame:
##   row 0: front-facing idle (8 near-identical frames) — brief spawn pose
##          only, matching the boss/grunt convention.
##   row 1: side-view bank/hover loop, all 8 columns — the main flight
##          animation.
##   row 2: gun-fire. cols 0-2 no muzzle flash (wind-up), cols 3-7 have a
##          visible flash — one shot spawned per flash frame, shown briefly
##          whenever the base class's fire cooldown actually fires.
##   row 3: thruster boost — cols 0-1 no flame, cols 2-7 show a growing
##          thruster flame beneath. Used for a periodic speed-burst dash
##          toward the player, since the art clearly supports one and the
##          original version never used anything but a static texture.
##   row 4: death. cols 0-3 damaged/sparking, col 4 crumbling, col 5 the
##          explosion, cols 6-7 falling wreckage (frozen on col 7).

const HitFeedback = preload("res://fx/hit_feedback.gd")
const GroundNav = preload("res://enemies/ground_nav.gd")
const Explosion = preload("res://fx/explosion.gd")

const ROW_IDLE := 0
const ROW_FLY := 1
const ROW_FIRE := 2
const ROW_BOOST := 3
const ROW_DEATH := 4
const FRAME_COLS := 8

const FIRE_FLASH_COLS := [3, 4, 5, 6, 7]
const FIRE_POSE_TIME := 0.5 # how long the fire animation shows after a shot
const DEATH_FRAME_COLS := [0, 2, 4, 5, 7]
const FRAME_TIME := 0.09

@export var bob_amplitude: float = 40.0
@export var bob_frequency: float = 1.6
@export var boost_interval: float = 4.0
@export var boost_duration: float = 1.0
@export var boost_speed_multiplier: float = 2.2
@export var standoff_distance: float = 300.0 # how close it closes before holding station
@export var hover_height: float = 210.0 # how far above the ground below it tries to cruise
@export var climb_speed: float = 90.0   # px/s it adjusts that cruising height by

var _base_y: float
var _base_y_set: bool = false
var _time: float = 0.0
var _fire_pose_timer: float = 0.0
var _boost_timer: float = 0.0
var _boosting: bool = false
var _dead: bool = false
var _death_timer: float = 0.0

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	enemy_name = "flyer_squadron"
	max_health = 20.0
	move_speed = 130.0
	fire_rate = 1.0 # drones now hold station, so they get to actually shoot at you
	contact_damage = 9.0 # was 20: brushing a drone shouldn't cost a fifth of your health
	health_bar_height = 70.0 # origin is the drone's center; hull half-height is ~47
	# barrel tip measured off row 2 col 5's muzzle flash: (165, 110) in a
	# 184x210 frame whose center sits at the sprite node's (4.8, 0) at 0.8 scale
	muzzle_offset = Vector2(63.2, 4.0)
	super._ready()
	_fire_cooldown = randf_range(0.2, fire_rate) # stagger so a squadron doesn't fire in unison
	_boost_timer = randf_range(boost_interval * 0.3, boost_interval) # stagger boosts too

func _physics_process(delta: float) -> void:
	if global_position.y > fall_death_y:
		queue_free()
		return
	if _dead:
		_process_death(delta)
		return

	if not _base_y_set:
		_base_y = global_position.y
		_base_y_set = true

	_time += delta
	_boost_timer -= delta
	if _boost_timer <= 0.0:
		if _boosting:
			_boosting = false
			_boost_timer = boost_interval
		else:
			_boosting = true
			_boost_timer = boost_duration

	var speed: float = move_speed * boost_speed_multiplier if _boosting else move_speed
	# Used to fly left unconditionally, which meant a drone crossed the screen
	# once and then receded forever -- you never fought it, it just left. Now it
	# closes to standoff_distance and holds there, so it reads as something
	# circling you and shooting.
	var player := get_tree().get_first_node_in_group("player")
	if player:
		var dx: float = player.global_position.x - global_position.x
		if absf(dx) > standoff_distance:
			velocity.x = signf(dx) * speed
		else:
			velocity.x = -signf(dx) * speed * 0.35 # drift back out to standoff
		sprite.flip_h = velocity.x < 0.0 # art faces RIGHT by default (gun barrel points right in row 2)
	else:
		velocity.x = -speed
	velocity.y = 0.0
	move_and_slide()
	global_position.y = _base_y + sin(_time * bob_frequency) * bob_amplitude

	# Hold an altitude relative to whatever is under it. The drone used to fly
	# at a fixed y forever, so any route that climbed left it either buried in a
	# building or so far overhead you couldn't reach it. It now drifts its
	# cruising height to stay hover_height above the ground below.
	var floor_y := GroundNav.ground_height_below(self, 900.0)
	if floor_y != INF:
		_base_y = move_toward(_base_y, floor_y - hover_height, climb_speed * delta)

	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var other := collision.get_collider()
		if other and other.is_in_group("player") and other.has_method("take_damage"):
			other.take_damage(contact_damage, self)

	if _fire_pose_timer > 0.0:
		_fire_pose_timer -= delta

	if enemy_projectile_scene:
		_fire_cooldown -= delta
		if _fire_cooldown <= 0.0:
			_try_fire_at_player() # inherited from enemy_base.gd -- also resets _fire_cooldown
			_fire_pose_timer = FIRE_POSE_TIME

	_update_animation()

func _update_animation() -> void:
	if _fire_pose_timer > 0.0:
		var t: float = 1.0 - (_fire_pose_timer / FIRE_POSE_TIME)
		var col: int = FIRE_FLASH_COLS[clampi(int(t * FIRE_FLASH_COLS.size()), 0, FIRE_FLASH_COLS.size() - 1)]
		sprite.frame = ROW_FIRE * FRAME_COLS + col
	elif _boosting:
		sprite.frame = ROW_BOOST * FRAME_COLS + 2 + (int(_time / FRAME_TIME) % 6)
	else:
		sprite.frame = ROW_FLY * FRAME_COLS + (int(_time / FRAME_TIME) % FRAME_COLS)

func take_damage(amount: float) -> void:
	if _dead:
		return
	health -= amount
	HitFeedback.flash_hit(sprite)
	queue_redraw()
	if health <= 0.0:
		_dead = true
		_death_timer = 0.0
		velocity = Vector2.ZERO
		Explosion.spawn(self, global_position, 70.0)
		Audio.play("enemy_down")

func _process_death(delta: float) -> void:
	_death_timer += delta
	var idx: int = min(int(_death_timer / (FRAME_TIME * 2.0)), DEATH_FRAME_COLS.size() - 1)
	sprite.frame = ROW_DEATH * FRAME_COLS + DEATH_FRAME_COLS[idx]
	global_position.y += 40.0 * delta # falls once it's dead, doesn't just hang in the air
	if idx >= DEATH_FRAME_COLS.size() - 1 and _death_timer > DEATH_FRAME_COLS.size() * FRAME_TIME * 2.0 + 0.6:
		EventBus.enemy_defeated.emit(enemy_name, global_position)
		queue_free()
