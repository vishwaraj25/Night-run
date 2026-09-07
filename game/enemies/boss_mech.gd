extends "res://enemies/enemy_base.gd"
## The end-of-level mech boss. Overrides enemy_base.gd's _physics_process
## entirely (like enemy_flyer.gd does) since it needs a real state machine
## instead of the base "walk left and maybe shoot" behavior: a front-facing
## spawn pose, a walk cycle, two distinct attacks with their own wind-up
## animations, and a multi-frame death sequence -- none of which the base
## enemy contract has any concept of.
##
## Sprite sheet: boss_mech_spritesheet.png, 8 cols x 5 rows, every row
## verified frame-by-frame before writing this:
##   row 0: front-facing idle (8 near-identical frames) -- used only for the
##          brief "boss appears" beat before the fight starts; the rest of
##          the sheet is side-view, matching the side-scroller.
##   row 1: side-view walk cycle, all 8 columns.
##   row 2: gun-fire. cols 0-2 are gun-raised with no muzzle flash (the
##          wind-up), cols 3-7 show a visible flash -- those are the actual
##          firing frames, one shot spawned per flash frame.
##   row 3: rocket charge-up. cols 0-1 pods retracted, 2-3 rising and
##          starting to glow, 4-5 full white-hot glow (the release point --
##          twin rockets spawn here, one per pod), 6 fading, 7 back to
##          retracted.
##   row 4: death. cols 0-3 progressively more damaged standing poses,
##          col 4 crumbling with smoke, col 5 the explosion itself, cols 6-7
##          final wreckage on the ground (frozen on col 7).

const HitFeedback = preload("res://fx/hit_feedback.gd")
const Explosion = preload("res://fx/explosion.gd")
const GroundNav = preload("res://enemies/ground_nav.gd")

const ROW_IDLE := 0
const ROW_WALK := 1
const ROW_FIRE := 2
const ROW_ROCKET := 3
const ROW_DEATH := 4
const FRAME_COLS := 8

const FIRE_FLASH_COLS := [3, 4, 5, 6, 7]
const ROCKET_RELEASE_COLS := [4, 5]
const FRAME_TIME := 0.1

enum State { INTRO, WALK, GUN_FIRE, ROCKET_ATTACK, LASER_SWEEP, DEAD }

@export var phase_2_health_pct: float = 0.6
@export var phase_3_health_pct: float = 0.3

## --- sweeping laser ---
## The timing attack, and the one thing the shield cannot turn. It pivots down
## from the gun, so where you are matters: high sweep, stand on the floor; low
## sweep, get up on a ledge; or jump it as it passes. At the distance you
## usually fight from (~1200px) the beam travels ~590px/s vertically and
## crosses a 150px body in about a quarter second -- your jump has 0.74s of
## air time and reaches its apex in 0.37s, so it is tight but genuinely fair.
@export var laser_charge_time: float = 0.8
@export var laser_sweep_time: float = 1.6
@export var laser_hold_time: float = 0.25
@export var laser_start_angle_deg: float = -35.0
@export var laser_end_angle_deg: float = 10.0
@export var laser_range: float = 1700.0
@export var laser_half_width: float = 26.0
@export var laser_damage: float = 15.0   # per landed tick; the player's own i-frames pace it to ~18/s
@export var laser_tick: float = 0.25
@export var add_scene: PackedScene            # sentry bot spawned as an "add" in phase 3

## Phase rewards. Surviving a phase drops a medkit and a better gun into the
## arena, so a long fight doesn't just grind you down with no way to recover
## and no reason to keep pushing. Dropped behind the boss, on the far side, so
## collecting one means crossing the arena rather than picking it up for free.
@export var crate_scene: PackedScene
@export var phase_2_weapon_scene: PackedScene   # dropped entering phase 2
@export var phase_3_weapon_scene: PackedScene   # dropped entering phase 3
@export var phase_drop_heal: float = 45.0

## Hard arena bounds, set by BossSpawner. Belt and braces over collision:
## the player's collision mask is terrain-only, so the player walks THROUGH
## enemies -- and when it walks through a 343px-wide boss, the physics solver
## ejects the boss sideways to resolve the overlap. A full playthrough had the
## player shove it clean through the 40px arena wall and off the end of the
## platform, where it fell out of the world. Collision cannot be relied on to
## contain something that is being pushed out of it, so the position is
## clamped outright.
@export var arena_min_x: float = -INF
@export var arena_max_x: float = INF
@export var add_spawn_interval: float = 6.0
@export var max_adds_alive: int = 2
@export var intro_duration: float = 1.2
@export var engage_range: float = 550.0
@export var gun_fire_damage: float = 10.0
@export var rocket_damage: float = 20.0
@export var attack_cooldown: float = 1.0
@export var rocket_attack_every_n: int = 3 # every Nth attack is the rocket volley instead of gunfire

var _state: State = State.INTRO
var _state_timer: float = 0.0
var _anim_col: int = 0
var _attack_count: int = 0
var _fired_this_attack: Dictionary = {}
var _phase: int = 1
var _death_done: bool = false
var _add_timer: float = 0.0
var _laser_t: float = 0.0        # 0 -> charge_time+sweep_time+hold_time
var _laser_angle: float = 0.0    # current beam angle, radians, in facing space
var _laser_dmg_timer: float = 0.0
var _parallel_mg: float = 0.0    # phase 3 only: MG cadence while the laser sweeps

## The art faces right; the boss advances left toward the player. Without this
## it walked and fired backwards through the whole fight.
func _face_player() -> void:
	var p := get_tree().get_first_node_in_group("player")
	if p:
		sprite.flip_h = p.global_position.x < global_position.x

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	enemy_name = "mech_boss"
	# 500 died in 6.5 seconds flat -- the player's MG does ~77 dps and nothing
	# about the fight had time to happen. At 1800 a perfect-uptime run is ~23s
	# and a realistic one with dodging lands near 45-60s, which is enough room
	# for all three phases to be things you actually experience.
	max_health = 1800.0
	move_speed = 55.0
	contact_damage = 16.0 # was 25; still the worst place to stand, just no longer a third of your health per touch
	health_bar_width = 0.0 # the boss reads off the HUD bar instead; two bars for one enemy is noise
	# barrel tip measured off row 2 col 5's muzzle flash: (172, 126) in a
	# 184x220 frame, carried through the sprite's (3.28, -220.8) at 2.186 scale
	muzzle_offset = Vector2(178.2, -185.8)
	health_bar_height = 375.0 # 338px tall mech standing on its origin
	super._ready()
	_state_timer = intro_duration

func _physics_process(delta: float) -> void:
	if global_position.y > fall_death_y:
		queue_free()
		return
	if _state == State.DEAD:
		_process_death(delta)
		return

	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y += gravity * delta

	_state_timer -= delta
	_process_adds(delta)

	match _state:
		State.INTRO:
			velocity.x = 0.0
			sprite.frame = ROW_IDLE * FRAME_COLS + (int(Time.get_ticks_msec() / 150.0) % FRAME_COLS)
			if _state_timer <= 0.0:
				_state = State.WALK
		State.WALK:
			_process_walk(delta)
		State.GUN_FIRE:
			velocity.x = 0.0
			_process_gun_fire()
		State.ROCKET_ATTACK:
			velocity.x = 0.0
			_process_rocket_attack()
		State.LASER_SWEEP:
			velocity.x = 0.0
			_process_laser(delta)

	move_and_slide()
	_clamp_to_arena()
	_apply_contact_damage()

## Contact damage by overlap test rather than by physics collision.
##
## The boss no longer masks the player's layer at all, which is the actual fix
## for it being displaced: the player's own mask is terrain-only, so the player
## walks through enemies, and a 343px boss with a player embedded in it gets
## ejected by the solver -- sideways through the arena wall, or, once x was
## clamped, straight up into the air. Ignoring the player's body entirely means
## nothing can shove it. The damage that collision used to provide is measured
## here instead.
func _apply_contact_damage() -> void:
	var p := get_tree().get_first_node_in_group("player")
	if not p or not p.has_method("take_damage"):
		return
	var shape := p.get_node_or_null("CollisionShape2D")
	if not shape or not (shape.shape is RectangleShape2D):
		return
	var half_p: Vector2 = (shape.shape as RectangleShape2D).size * 0.5
	var centre_p: Vector2 = shape.global_position
	# The mech's own box, from its scene: 343 x 338 centred 169 above the feet.
	var centre_b := global_position + Vector2(0.0, -169.4)
	var half_b := Vector2(171.6, 169.4)
	if absf(centre_p.x - centre_b.x) < half_p.x + half_b.x \
			and absf(centre_p.y - centre_b.y) < half_p.y + half_b.y:
		p.take_damage(contact_damage, self)

## Whatever happened during move_and_slide -- being walked through, being
## shoved into a wall -- the boss ends the frame inside its arena.
func _clamp_to_arena() -> void:
	if global_position.x < arena_min_x or global_position.x > arena_max_x:
		global_position.x = clampf(global_position.x, arena_min_x, arena_max_x)
		velocity.x = 0.0

func _process_walk(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	var dist_x: float = INF
	if player:
		dist_x = player.global_position.x - global_position.x
		# Close to engage_range, then stand and fight -- from EITHER side.
		#
		# This used to be "walk left unless the player is to the right and far
		# away", a leftover from when the boss was just another enemy advancing
		# down a side-scrolling street. In a sealed arena the player is often to
		# its left, and the old condition then walked it left at any distance
		# including zero: it shoved you into the arena wall and stood on top of
		# you, landing contact damage every invulnerability window until you
		# died. A bot that actually fought it died 38 times in one run.
		if absf(dist_x) > engage_range:
			velocity.x = signf(dist_x) * move_speed
		else:
			velocity.x = 0.0
	else:
		velocity.x = -move_speed

	# Stop at the edge of whatever it is standing on. The boss was the only
	# ground unit without this: chasing a player who had died and respawned
	# outside the arena, it walked straight off the edge and out of the world.
	# The probe distance is half its own 343px body, so it stops with its feet
	# still fully on the floor.
	if velocity.x != 0.0 and is_on_floor():
		if not GroundNav.has_ground_at(self, signf(velocity.x) * 175.0):
			velocity.x = 0.0

	sprite.frame = ROW_WALK * FRAME_COLS + (int(Time.get_ticks_msec() / 120.0) % FRAME_COLS)
	_face_player()

	if player and absf(dist_x) <= engage_range and _state_timer <= 0.0:
		_attack_count += 1
		_fired_this_attack.clear()
		# Phase 1 alternates gun and rockets. From phase 2 the laser enters the
		# rotation as every 3rd attack; in phase 3 it also carries MG fire
		# through the sweep, so you are jumping the beam and deflecting rounds
		# in the same beat.
		if _phase >= 2 and _attack_count % 3 == 0:
			_state = State.LASER_SWEEP
			Audio.play("boss_charge")
			_laser_t = 0.0
			_laser_dmg_timer = 0.0
			_parallel_mg = 0.0
			_state_timer = laser_charge_time + laser_sweep_time + laser_hold_time
			_anim_col = 0
		elif _attack_count % rocket_attack_every_n == 0:
			_state = State.ROCKET_ATTACK
			_state_timer = ROCKET_RELEASE_COLS[-1] * FRAME_TIME * 2.0 # full charge->release->reset cycle
			_anim_col = 0
		else:
			_state = State.GUN_FIRE
			_state_timer = FIRE_FLASH_COLS[-1] * FRAME_TIME + FRAME_TIME
			_anim_col = 0

func _process_gun_fire() -> void:
	_anim_col = clampi(int((FIRE_FLASH_COLS[-1] * FRAME_TIME + FRAME_TIME - _state_timer) / FRAME_TIME), 0, 7)
	sprite.frame = ROW_FIRE * FRAME_COLS + _anim_col
	_face_player()
	if _anim_col in FIRE_FLASH_COLS and not _fired_this_attack.has(_anim_col):
		_fired_this_attack[_anim_col] = true
		_fire_at_player(gun_fire_damage)
	if _state_timer <= 0.0:
		_state = State.WALK
		_state_timer = attack_cooldown

func _process_rocket_attack() -> void:
	var total_frames: float = 8.0
	var half_cycle: float = ROCKET_RELEASE_COLS[-1] * FRAME_TIME * 2.0
	var elapsed: float = half_cycle - _state_timer
	_anim_col = clampi(int(elapsed / FRAME_TIME), 0, 7)
	sprite.frame = ROW_ROCKET * FRAME_COLS + _anim_col
	_face_player()
	# A 500-HP boss whose two attacks look alike is unreadable. The rocket
	# charge ramps red through its pod-raise frames so the volley is something
	# you see coming and move for, exactly like the grunt's swing.
	var first_release: int = ROCKET_RELEASE_COLS[0]
	if _anim_col < first_release:
		HitFeedback.set_telegraph(sprite, float(_anim_col) / float(first_release))
	else:
		HitFeedback.set_telegraph(sprite, 1.0)
	if _anim_col in ROCKET_RELEASE_COLS and not _fired_this_attack.has(_anim_col):
		_fired_this_attack[_anim_col] = true
		_fire_at_player(rocket_damage)
	if _state_timer <= 0.0:
		_state = State.WALK
		_state_timer = attack_cooldown
		HitFeedback.set_telegraph(sprite, 0.0)

func _process_laser(delta: float) -> void:
	_laser_t += delta
	_face_player()
	# Hold the gun-raised pose through the charge, then the flash frames while
	# the beam is live, so the sheet still reads as "the gun is doing this".
	var charging: bool = _laser_t < laser_charge_time
	sprite.frame = ROW_FIRE * FRAME_COLS + (1 if charging else 5)

	if charging:
		# Long, obvious wind-up -- an undodgeable-looking beam needs a tell you
		# can act on well before it arrives, and half of that tell is the whine.
		HitFeedback.set_telegraph(sprite, _laser_t / laser_charge_time)
		_laser_angle = deg_to_rad(laser_start_angle_deg)
		queue_redraw()
		return

	HitFeedback.set_telegraph(sprite, 1.0)
	Audio.loop("boss_laser_loop")
	var swept: float = clampf((_laser_t - laser_charge_time) / laser_sweep_time, 0.0, 1.0)
	_laser_angle = deg_to_rad(lerpf(laser_start_angle_deg, laser_end_angle_deg, swept))
	queue_redraw()

	_laser_dmg_timer -= delta
	if _laser_dmg_timer <= 0.0:
		_laser_dmg_timer = laser_tick
		_laser_damage_check()

	# Phase 3: the MG keeps working through the sweep.
	if _phase >= 3:
		_parallel_mg -= delta
		if _parallel_mg <= 0.0:
			_parallel_mg = 0.35
			_fire_at_player(gun_fire_damage)

	if _laser_t >= laser_charge_time + laser_sweep_time + laser_hold_time:
		Audio.stop_loop("boss_laser_loop")
		HitFeedback.set_telegraph(sprite, 0.0)
		_state = State.WALK
		_state_timer = attack_cooldown
		queue_redraw()

## Beam origin and direction in world space. Mirrored with the sprite, so the
## beam always leaves the barrel it is drawn coming out of.
func _laser_ray() -> Array:
	var offset := muzzle_offset
	var facing := 1.0
	if sprite.flip_h:
		offset.x = -offset.x
		facing = -1.0
	var dir := Vector2(facing, 0.0).rotated(_laser_angle * facing)
	return [global_position + offset, dir]

func _laser_damage_check() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if not player or not player.has_method("take_damage"):
		return
	var ray := _laser_ray()
	var origin: Vector2 = ray[0]
	var dir: Vector2 = ray[1]
	var side := Vector2(-dir.y, dir.x)
	# Aim at the player's collision centre, not its origin (which is at the
	# feet) -- the same mistake that had the player's own laser passing over
	# every enemy shorter than it.
	var shape := player.get_node_or_null("CollisionShape2D")
	var centre: Vector2 = shape.global_position if shape else player.global_position
	var to_player: Vector2 = centre - origin
	var along: float = to_player.dot(dir)
	if along < 0.0 or along > laser_range:
		return
	if absf(to_player.dot(side)) > laser_half_width + 60.0: # +half the player's body
		return
	# deflectable = false: the shield halves this instead of turning it, so
	# turtling is not an answer to the beam.
	player.take_damage(laser_damage, self, false)

func _fire_at_player(damage_amount: float) -> void:
	if not enemy_projectile_scene:
		return
	var player := get_tree().get_first_node_in_group("player")
	if not player:
		return
	var muzzle := get_muzzle_position()
	var proj := enemy_projectile_scene.instantiate()
	proj.global_position = muzzle
	proj.global_rotation = (player.global_position - muzzle).angle()
	proj.set("damage", damage_amount)
	get_tree().current_scene.add_child(proj)

func _draw() -> void:
	super._draw() # the health bar, if this enemy has one
	if _state != State.LASER_SWEEP:
		return
	var ray := _laser_ray()
	var start: Vector2 = to_local(ray[0])
	var dir: Vector2 = ray[1]
	var charging: bool = _laser_t < laser_charge_time

	if charging:
		# Charge tell: a growing bloom at the muzzle plus a thin sight line
		# along where the beam will appear.
		var t: float = _laser_t / laser_charge_time
		draw_line(start, start + dir * laser_range, Color(1.0, 0.3, 0.3, 0.10 + 0.15 * t), 2.0)
		draw_circle(start, 10.0 + 26.0 * t, Color(1.0, 0.35, 0.2, 0.25 + 0.4 * t))
		draw_circle(start, 4.0 + 12.0 * t, Color(1.0, 0.95, 0.85, 0.9))
		return

	var end: Vector2 = start + dir * laser_range
	var boil: float = 1.0 + sin(_laser_t * 40.0) * 0.1
	draw_line(start, end, Color(1.0, 0.15, 0.15, 0.20), 46.0 * boil)
	draw_line(start, end, Color(1.0, 0.30, 0.25, 0.75), 22.0 * boil)
	draw_line(start, end, Color(1.0, 0.95, 0.92, 0.95), 8.0 * boil)
	draw_circle(start, 22.0 * boil, Color(1.0, 0.9, 0.8, 0.9))

func take_damage(amount: float, source: Node = null) -> void:
	if _state == State.DEAD:
		return
	health -= amount
	HitFeedback.flash_hit(sprite)
	queue_redraw()
	if source and source.has_method("take_damage"):
		pass # no counter-deflect against a boss; kept for signature parity with the player's shield system
	EventBus.boss_health_changed.emit(health, max_health)
	_update_phase()
	if health <= 0.0:
		_start_death()

## Three scripted phases, each changing what you have to do rather than just
## scaling numbers:
##   1 -- walk + gunfire. Learn the wind-up (row 2 cols 0-2) and the range.
##   2 -- at 50%: faster, shorter cooldown, and every 2nd attack is a rocket
##        volley instead of every 3rd, so you have to keep using the ledges.
##   3 -- at 25%: rockets every other attack AND grunt adds, so you can no
##        longer stand still and duel it.
func _update_phase() -> void:
	var target := 1
	if health <= max_health * phase_3_health_pct:
		target = 3
	elif health <= max_health * phase_2_health_pct:
		target = 2
	if target <= _phase:
		return
	_phase = target
	if _phase == 2:
		move_speed *= 1.4
		attack_cooldown *= 0.7
		rocket_attack_every_n = 2
		_drop_phase_reward(phase_2_weapon_scene, "double_mg")
	elif _phase == 3:
		move_speed *= 1.15
		attack_cooldown *= 0.75
		_add_timer = 1.0 # first wave arrives almost immediately
		_drop_phase_reward(phase_3_weapon_scene, "laser")
	EventBus.boss_phase_changed.emit(_phase)

## A medkit and a weapon, dropped just past the player on the side away from
## the boss. The first version dropped them behind the boss, which meant
## crossing a 340px mech to collect them -- a test run reached neither.
## Deferred because this runs inside take_damage, which is called from a
## projectile's collision callback: adding children to the tree there is not
## allowed.
func _drop_phase_reward(weapon: PackedScene, weapon_item: String) -> void:
	if crate_scene == null:
		return
	var player := get_tree().get_first_node_in_group("player")
	var anchor: Vector2 = player.global_position if player else global_position
	var away: float = signf(anchor.x - global_position.x)
	if away == 0.0:
		away = -1.0
	# Height comes from the boss, not the player: the boss is always standing
	# on the arena floor, whereas the player might be up on a ledge when the
	# phase flips, which would leave the crates floating out of reach once
	# they dropped back down.
	var drop_y: float = global_position.y - 40.0
	_spawn_crate.call_deferred("medkit", null, Vector2(anchor.x + away * 130.0, drop_y))
	if weapon:
		_spawn_crate.call_deferred(weapon_item, weapon, Vector2(anchor.x + away * 250.0, drop_y))

func _spawn_crate(item_name: String, weapon: PackedScene, at: Vector2) -> void:
	var crate := crate_scene.instantiate()
	crate.item_name = item_name
	crate.heal_amount = phase_drop_heal
	if weapon:
		crate.weapon_scene = weapon
		crate.weapon_seconds = 9999.0 # keep it for the rest of the fight
	get_tree().current_scene.add_child(crate)
	crate.global_position = at

## Phase 3 only. Adds are capped and tracked by group so a slow player can't
## accumulate a screen full of grunts.
func _process_adds(delta: float) -> void:
	if _phase < 3 or add_scene == null:
		return
	_add_timer -= delta
	if _add_timer > 0.0:
		return
	_add_timer = add_spawn_interval
	var alive := 0
	for n in get_tree().get_nodes_in_group("boss_add"):
		if is_instance_valid(n):
			alive += 1
	if alive >= max_adds_alive:
		return
	var add := add_scene.instantiate()
	# drop them out from behind the mech, on the side it's facing away from
	add.global_position = global_position + Vector2(220.0 if sprite.flip_h else -220.0, -40.0)
	add.add_to_group("boss_add")
	get_tree().current_scene.add_child(add)

func _start_death() -> void:
	Audio.stop_loop("boss_laser_loop")
	HitFeedback.set_telegraph(sprite, 0.0)
	queue_redraw() # drop the beam if it died mid-sweep
	Explosion.spawn(self, global_position + Vector2(0, -170), 260.0) # sized to the mech, not to a drone
	_state = State.DEAD
	_state_timer = 0.0
	velocity = Vector2.ZERO

func _process_death(delta: float) -> void:
	_state_timer += delta
	var col: int = clampi(int(_state_timer / (FRAME_TIME * 1.5)), 0, 7)
	sprite.frame = ROW_DEATH * FRAME_COLS + col
	if col >= 5 and not _death_done:
		_death_done = true
		EventBus.boss_defeated.emit()
	if col >= 7 and _state_timer > 7 * FRAME_TIME * 1.5 + 1.0:
		queue_free()
