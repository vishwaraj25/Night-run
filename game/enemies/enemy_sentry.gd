extends "res://enemies/enemy_base.gd"
## Mobile ranged ground enemy: a walking sentry that keeps its distance and
## shoots. Replaced the clawed melee grunt, which had no way to shoot back and
## so died before it ever reached you.
##
## Sprite sheet: turret_sentry_spritesheet.png, 8 cols x 5 rows, every row
## checked frame by frame, chroma-keyed off magenta and row-aligned to a
## single ground line (the rows arrived with their feet 25px apart, which
## would have made the sprite jump every time it opened fire):
##   row 0: idle, barrel level -- also stands in for the walk, since the sheet
##          has no walk cycle; the stride bob sells the movement.
##   row 1: idle with the barrel raised slightly. Used while it holds station
##          in range, so "parked and watching you" looks different from
##          "repositioning".
##   row 2: fire, level. cols 0-2 are the wind-up with no flash -- that's what
##          the red telegraph ramps across -- and cols 3-7 carry the flash.
##   row 3: fire, angled up. Same split, used when the player is above it.
##   row 4: death: damaged, sparking, exploding, then wreckage on the ground.

const HitFeedback = preload("res://fx/hit_feedback.gd")
const GroundNav = preload("res://enemies/ground_nav.gd")
const Explosion = preload("res://fx/explosion.gd")

const FRAME_COLS := 8
const ROW_IDLE := 0
const ROW_WATCH := 1
const ROW_FIRE := 2
const ROW_FIRE_UP := 3
const ROW_DEATH := 4

const FIRE_WINDUP_COLS := 3   # cols 0-2 have no muzzle flash
const FRAME_TIME := 0.07
const DEATH_FRAME_TIME := 0.11

@export var preferred_range: float = 380.0  # tries to hold this gap and shoot from it
@export var retreat_range: float = 220.0    # backs off if the player closes inside this
@export var telegraph_time: float = 0.35    # red wind-up before each shot
@export var aim_up_threshold: float = 90.0  # player this far above -> use the angled-up pose
@export var jump_velocity: float = -520.0
@export var edge_probe_distance: float = 70.0
@export var bob_amount: float = 3.0
@export var dead_linger: float = 1.6

var _face_dir: float = -1.0
var _fire_anim: float = -1.0   # >= 0 while the firing animation is playing
var _aiming_up: bool = false
var _dead: bool = false
var _dead_timer: float = 0.0
var _bob_time: float = 0.0
var _sprite_base_y: float = 0.0
var _moving: bool = false

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	enemy_name = "sentry_bot"
	max_health = 30.0
	move_speed = 110.0
	contact_damage = 6.0 # walking into it should sting, not gut you -- the gun is the threat
	fire_rate = 0.95 # was 1.5; a shooter that fires under once a second isn't pressure
	fire_range = 520.0
	health_bar_height = 165.0
	super._ready()
	_sprite_base_y = sprite.position.y
	_fire_cooldown = randf_range(0.4, fire_rate) # stagger so a group doesn't volley in unison

func _physics_process(delta: float) -> void:
	if global_position.y > fall_death_y:
		queue_free()
		return
	if _dead:
		_dead_timer += delta
		_animate_death()
		if _dead_timer > dead_linger:
			queue_free()
		return

	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y += gravity * delta

	_bob_time += delta
	if _fire_anim >= 0.0:
		_fire_anim += delta
		if _fire_anim > FRAME_COLS * FRAME_TIME:
			_fire_anim = -1.0

	_process_engagement(delta)
	move_and_slide()

	# A stride bob so a sheet with no walk cycle doesn't read as a frozen prop
	# sliding along the ground.
	sprite.position.y = _sprite_base_y + (sin(_bob_time * 9.0) * bob_amount if _moving else 0.0)
	_animate()

	for i in get_slide_collision_count():
		var other := get_slide_collision(i).get_collider()
		if other and other.is_in_group("player") and other.has_method("take_damage"):
			other.take_damage(contact_damage, self)

func _process_engagement(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if not player:
		velocity.x = 0.0
		_moving = false
		return

	var dist: float = player.global_position.x - global_position.x
	_face_dir = signf(dist) if dist != 0.0 else _face_dir
	sprite.flip_h = _face_dir < 0.0 # the sheet's barrel points right by default
	_aiming_up = (global_position.y - player.global_position.y) > aim_up_threshold

	# Hold the gap: close if too far, back off if the player is on top of it.
	var want := 0.0
	if absf(dist) > preferred_range:
		want = _face_dir
	elif absf(dist) < retreat_range:
		want = -_face_dir
	var step := _safe_step(want)
	velocity.x = step * move_speed
	_moving = step != 0.0

	# Fire, with a visible wind-up so it's dodgeable on sight.
	if enemy_projectile_scene and global_position.distance_to(player.global_position) <= fire_range:
		_fire_cooldown -= delta
		HitFeedback.set_telegraph(sprite,
			1.0 - (_fire_cooldown / telegraph_time) if _fire_cooldown < telegraph_time else 0.0)
		if _fire_cooldown <= 0.0:
			_try_fire_at_player() # inherited: fires from muzzle_offset and resets the cooldown
			_fire_anim = 0.0
			HitFeedback.set_telegraph(sprite, 0.0)
	else:
		HitFeedback.set_telegraph(sprite, 0.0)

func _animate() -> void:
	var row: int
	var col: int
	if _fire_anim >= 0.0:
		row = ROW_FIRE_UP if _aiming_up else ROW_FIRE
		col = clampi(int(_fire_anim / FRAME_TIME), 0, FRAME_COLS - 1)
	else:
		# Watching pose while it holds station, idle cycle while it moves --
		# two readable states rather than one frozen frame.
		row = ROW_IDLE if _moving else ROW_WATCH
		col = int(_bob_time / 0.13) % FRAME_COLS
	sprite.frame = row * FRAME_COLS + col

func _animate_death() -> void:
	var col: int = clampi(int(_dead_timer / DEATH_FRAME_TIME), 0, FRAME_COLS - 1)
	sprite.frame = ROW_DEATH * FRAME_COLS + col

## Same terrain rules the ground enemies share: never step into a gap it can't
## cross, and hop anything solid in the way.
func _safe_step(want: float) -> float:
	if want == 0.0 or not is_on_floor():
		return want
	if GroundNav.wall_ahead(self, want):
		velocity.y = jump_velocity
		return want
	if not GroundNav.has_ground_at(self, want * edge_probe_distance):
		var reach := GroundNav.jump_reach(jump_velocity, gravity, move_speed)
		if GroundNav.gap_is_crossable(self, want, reach):
			velocity.y = jump_velocity
			return want
		return 0.0
	return want

## Signature must match enemy_base.gd's take_damage(float) -> void exactly --
## GDScript rejects the script outright otherwise, which silently removed every
## ground enemy from the level.
func take_damage(amount: float) -> void:
	if _dead:
		return
	health -= amount
	HitFeedback.flash_hit(sprite)
	queue_redraw()
	if health <= 0.0:
		_dead = true
		_dead_timer = 0.0
		velocity = Vector2.ZERO
		HitFeedback.set_telegraph(sprite, 0.0)
		Explosion.spawn(self, global_position + Vector2(0, -60), 85.0)
		Audio.play("enemy_down")
		EventBus.enemy_defeated.emit(enemy_name, global_position)
