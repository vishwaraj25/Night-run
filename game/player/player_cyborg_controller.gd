extends CharacterBody2D
## Humanoid replacement for car_controller.gd — same physics constants so it
## drops into the existing level (jump gaps, ramps, strut clearances) without
## re-tuning anything.
##
## Sprite sheet: player_cyborg_spritesheet.png (v4 — the white-haired/red-eye
## design, regenerated to hold a rifle in every pose, not just while aiming).
## 8 columns x 5 rows, every frame verified full-body before writing this:
##   row 0 col 0-7: idle, all 8 real standing variations, gun visibly held
##   row 1 col 0-7: run cycle, gun visibly held throughout
##   row 2 col 0:   crouch pose · col 2: leap/rising pose (legs pushing off) ·
##                  col 3: falling pose (full-body extension, cape trailing) ·
##                  cols 1,4-7 are more crouch/landing variants, unused here
##   row 3:         aim poses, still only 3 real directions after 3 regen
##                  attempts — col 0 = forward-level, col 1 = forward-up,
##                  col 3 = forward-down. No "aiming behind" frame exists in
##                  any regeneration tried so far, so that's handled in code
##                  instead (see _aim_column): flip_h follows the aim
##                  direction while firing, mirroring these 3 poses to face
##                  wherever you're actually aiming.
##   row 4 col 0:   stagger/hit-reaction pose (not wired up, still using the
##                  modulate-flash approach since that already works) ·
##                  col 1-3: death sequence (falling → collapsing → down) ·
##                  col 4-7: more lying-flat variants, unused here.
## flip_h tracks movement-facing normally, except while firing (see
## _update_animation), when it follows the aim direction instead — every row
## here is drawn facing right, so mirroring composes correctly either way.

const ROW_IDLE := 0
const ROW_RUN := 1
const ROW_ACTION := 2 # leap / fall / crouch all live on this row
const ROW_AIM := 3
const ROW_DEATH := 4

const FRAME_COLS := 8
const IDLE_COLS := [0, 1, 2, 3, 4, 5, 6, 7]

const LEAP_COL := 2
const FALL_COL := 3
const CROUCH_COL := 0

const AIM_FORWARD_COL := 0
const AIM_DOWN_COL := 3
const AIM_UP_COL := 1

const DEATH_FRAME_COLS := [1, 2, 3]
const DEATH_FRAME_TIME := 0.15

const move_speed := 260.0
const crouch_speed := 60.0
const accel := 1600.0
const friction := 1400.0
const gravity := 1400.0
const jump_velocity := -520.0
const max_jumps := 2
const fall_death_y := 1100.0

const max_health := 100.0
const hit_invulnerability_time := 0.85 # was 0.6; contact damage repeats on this timer, so it sets the worst-case dps of standing in something

## Jetpack pickup: hold jump while airborne to thrust. Deliberately weaker
## than gravity in raw terms and capped by max_rise_speed, so it reads as a
## controlled hover-climb rather than flight -- you can reach the high routes
## and hang over a fight, but you can't just fly the level.
const jetpack_thrust := 2600.0
const jetpack_max_rise := -300.0

## Shield. Hold the shield key to raise it: while it's up and has charge,
## incoming fire is deflected outright rather than chipped down -- enemy
## bullets reverse and fly back at whoever shot them (enemy_projectile.gd has
## always supported that, there was just never a shield to trigger it).
## The drain is what stops it being a permanent answer: about three and a half
## seconds of continuous block, and it only starts recovering once you drop it.
## Tuned up from 40/s drain after a test run held it through a firefight and
## ran dry in 2.5s -- long enough to prove the mechanic, too short to actually
## use it as an answer to a shooter.
const shield_max := 100.0
const shield_drain_per_sec := 28.0
const shield_regen_per_sec := 30.0
const shield_regen_delay := 0.7
const shield_block_cost := 8.0    # each blocked hit costs charge on top of the drain
## Raising the shield opens a short window where a hit is not just blocked but
## PERFECTLY deflected: no charge spent, and the round goes back twice as fast
## for twice the damage. Past the window it degrades to the ordinary block --
## still safe, still reverses the bullet, but it drains you and the return shot
## is weak. Two tools out of one button: a panic block that costs, and a timing
## skill that pays.
const shield_perfect_window := 0.2

signal health_changed(current: float, max: float)
signal jetpack_changed(seconds_left: float, total: float)
signal shield_energy_changed(current: float, max_energy: float)
signal shield_changed(active: bool)

var health := max_health
var _jumps_used := 0
var _was_airborne := false
var _invuln_timer := 0.0
var _dead := false
var _death_timer := 0.0
var _facing := 1.0        # last horizontal direction moved; what "forward" means when aiming
var _mouse_aim := false   # last aim input came from the mouse rather than the keyboard
var shield_energy := shield_max
var shield_active := false
var last_block_perfect := false  # read by enemy_projectile.gd to size the return shot
var _shield_idle := 0.0   # time since the shield was last used, for the regen delay
var _shield_held := 0.0   # how long the shield has been up this raise
var jetpack_time := 0.0   # seconds of jetpack fuel left; the HUD reads this
var jetpack_duration := 0.0 # what it started at, so the HUD can show a fraction

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	add_to_group("player") # HUD, enemy targeting, and weapon aim assist all look for this group

func _physics_process(delta: float) -> void:
	if _dead:
		_process_death(delta)
		return

	queue_redraw() # the shield bubble is drawn on this node
	if _invuln_timer > 0.0:
		_invuln_timer -= delta
		sprite.modulate = Color(2, 2, 2) if int(_invuln_timer * 20) % 2 == 0 else Color(1, 1, 1)
	else:
		sprite.modulate = Color(1, 1, 1)

	if not is_on_floor():
		velocity.y += gravity * delta
	else:
		if _was_airborne:
			_jumps_used = 0
	_was_airborne = not is_on_floor()

	_update_shield(delta)

	var crouching := is_on_floor() and Input.is_action_pressed("crouch")

	var move_input := Input.get_axis("move_backward", "move_forward")
	var target_speed := crouch_speed if crouching else move_speed
	if move_input != 0.0:
		velocity.x = move_toward(velocity.x, move_input * target_speed, accel * delta)
		sprite.flip_h = move_input < 0.0
		_facing = signf(move_input)
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)

	if Input.is_action_just_pressed("jump") and not crouching and _jumps_used < max_jumps:
		velocity.y = jump_velocity
		_jumps_used += 1
		Audio.play("jump")

	if jetpack_time > 0.0:
		jetpack_time = max(0.0, jetpack_time - delta)
		# Held jump in the air burns fuel and climbs. Tapping jump off the
		# ground still does a normal jump first -- the pack extends the jump,
		# it doesn't replace it, so the controls never change under you.
		if Input.is_action_pressed("jump") and not is_on_floor():
			velocity.y = maxf(velocity.y - jetpack_thrust * delta, jetpack_max_rise)
			_jumps_used = 0 # the pack refunds the air jump while it's burning
		jetpack_changed.emit(jetpack_time, jetpack_duration)
		if jetpack_time <= 0.0:
			jetpack_duration = 0.0

	move_and_slide()

	_update_animation(move_input, crouching)

	if global_position.y > fall_death_y:
		_die("fell")

## Whichever device you touched last wins, so neither control scheme has to
## be "the" one: nudging the mouse switches to mouse aim, touching an aim or
## movement key switches back to keyboard.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_aim = true
	elif event is InputEventKey and event.pressed and not event.echo:
		_mouse_aim = false

## The single source of truth for where this character is shooting -- the
## animation code and WeaponManager both read this, so the pose on screen and
## the direction bullets actually leave in can no longer disagree.
##
## Keyboard aim is the Contra scheme the game was specced for: forward along
## your facing, Up to angle up, Down (in the air, where it isn't crouch) to
## angle down. Requiring the mouse for this was most of why the shooting felt
## awkward -- you had to steer a cursor with one hand while platforming with
## the other.
func get_aim_direction() -> Vector2:
	if not Input.is_action_pressed("fire"):
		return Vector2.ZERO

	if _mouse_aim:
		var to_mouse := get_global_mouse_position() - global_position
		if to_mouse.length() >= 1.0:
			return to_mouse.normalized()

	var vertical := 0.0
	if Input.is_action_pressed("lane_up"):
		vertical = -1.0
	elif Input.is_action_pressed("lane_down") and not is_on_floor():
		vertical = 1.0 # on the ground Down is crouch, so diagonal-down is an air move
	if vertical == 0.0:
		return Vector2(_facing, 0.0)
	# Keep a little horizontal in it even for a "straight" up/down shot: the
	# sign of x is what tells the sprite and the weapon which way to face, and
	# a pure Vector2(0, -1) would silently snap both back to facing right.
	return Vector2(_facing * 0.35, vertical).normalized()

func _get_aim_vector() -> Vector2:
	return get_aim_direction()

## Collapses the aim vector to one of the 3 real directions the art
## supports. There's no "aiming behind" frame in this sheet (3 regenerations
## in a row all failed to produce one), so instead of a dedicated pose, aim
## fully reorients the character: flip_h follows the aim's own horizontal
## sign while firing, mirroring the forward/up/down pose to face wherever
## you're actually shooting instead of showing a wrong-facing frame.
func _aim_column(aim_vec: Vector2) -> int:
	if aim_vec.y < -0.4:
		return AIM_UP_COL
	if aim_vec.y > 0.4:
		return AIM_DOWN_COL
	return AIM_FORWARD_COL

func _update_animation(move_input: float, crouching: bool) -> void:
	var aim_vec := _get_aim_vector()
	var row: int
	var col: int

	if crouching:
		row = ROW_ACTION
		col = CROUCH_COL
	elif not is_on_floor():
		row = ROW_ACTION
		col = LEAP_COL if velocity.y < 0.0 else FALL_COL
	elif aim_vec != Vector2.ZERO:
		row = ROW_AIM
		col = _aim_column(aim_vec)
		sprite.flip_h = aim_vec.x < 0.0 # face the aim direction, overriding movement-facing while firing
	elif move_input != 0.0:
		row = ROW_RUN
		col = int(Time.get_ticks_msec() / 80.0) % FRAME_COLS # 80ms/frame run cycle, retune to taste
	else:
		row = ROW_IDLE
		col = IDLE_COLS[int(Time.get_ticks_msec() / 200.0) % IDLE_COLS.size()]

	sprite.frame = row * FRAME_COLS + col

func _process_death(delta: float) -> void:
	_death_timer += delta
	var idx: int = min(int(_death_timer / DEATH_FRAME_TIME), DEATH_FRAME_COLS.size() - 1)
	sprite.frame = ROW_DEATH * FRAME_COLS + DEATH_FRAME_COLS[idx]
	velocity = Vector2.ZERO

## Matches car_controller.gd's contract (amount, source, returns whether the
## hit was deflected) so enemy_base.gd's `other.take_damage(contact_damage,
## self)` works against this controller too. Returns whether the hit was
## blocked, which is what turns an enemy bullet around.
func _update_shield(delta: float) -> void:
	var want: bool = Input.is_action_pressed("shield") and shield_energy > 0.0
	if want:
		if not shield_active:
			_shield_held = 0.0 # a fresh raise reopens the perfect window
		_shield_held += delta
		shield_energy = maxf(0.0, shield_energy - shield_drain_per_sec * delta)
		_shield_idle = 0.0
	else:
		_shield_held = 0.0
		_shield_idle += delta
		if _shield_idle >= shield_regen_delay:
			shield_energy = minf(shield_max, shield_energy + shield_regen_per_sec * delta)
	if want != shield_active:
		shield_active = want
		if shield_active:
			Audio.play("shield_up")
		shield_changed.emit(shield_active)
	shield_energy_changed.emit(shield_energy, shield_max)

## `deflectable` is false for things the shield cannot turn -- the boss's
## sweeping laser, chiefly. Those get halved rather than blocked, so the shield
## is never a universal answer and the beam still has to be dodged.
func take_damage(amount: float, _source: Node = null, deflectable: bool = true) -> bool:
	if _dead:
		return false
	if shield_active and shield_energy > 0.0:
		if not deflectable:
			amount *= 0.5 # brace against it; you still take the hit
		else:
			last_block_perfect = _shield_held <= shield_perfect_window
			Audio.play("deflect" if last_block_perfect else "hit_enemy")
			if not last_block_perfect:
				shield_energy = maxf(0.0, shield_energy - shield_block_cost)
			shield_energy_changed.emit(shield_energy, shield_max)
			return true
	if _invuln_timer > 0.0:
		return false
	_invuln_timer = hit_invulnerability_time
	Audio.play("player_hurt")
	health = max(0.0, health - amount)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		_die("defeated")
	return false

## Put the character back in play at `at`. Public because level.gd owns the
## checkpoint logic and shouldn't be reaching into this script's private death
## state to do it.
func respawn(at: Vector2) -> void:
	global_position = at
	velocity = Vector2.ZERO
	_dead = false
	_death_timer = 0.0
	_invuln_timer = hit_invulnerability_time * 2.0 # a moment's grace on arrival
	_jumps_used = 0
	health = max_health
	shield_energy = shield_max
	sprite.modulate = Color(1, 1, 1)
	health_changed.emit(health, max_health)
	shield_energy_changed.emit(shield_energy, shield_max)

func _die(reason: String) -> void:
	if _dead:
		return
	_dead = true
	_death_timer = 0.0
	EventBus.player_died.emit(reason)


## Pickup entry points. Kept as methods on the controller (rather than the
## crate reaching into fields) so the crate doesn't need to know how health or
## fuel are stored.
func heal(amount: float) -> void:
	if _dead:
		return
	health = minf(max_health, health + amount)
	health_changed.emit(health, max_health)

func grant_jetpack(seconds: float) -> void:
	if _dead:
		return
	jetpack_time = seconds   # a second pack refills rather than stacking
	jetpack_duration = seconds
	jetpack_changed.emit(jetpack_time, jetpack_duration)


## The shield bubble. Drawn rather than sprited so it can pulse with the
## charge left in it -- a shield that looks the same at 5% as at 100% would
## strand you mid-block with no warning.
func _draw() -> void:
	if not shield_active or shield_energy <= 0.0:
		return
	var frac: float = clampf(shield_energy / shield_max, 0.0, 1.0)
	var centre := Vector2(0.0, -75.0)
	var r := 88.0
	var edge := Color(0.35, 0.8, 1.0).lerp(Color(1.0, 0.45, 0.3), 1.0 - frac)
	draw_circle(centre, r, Color(edge.r, edge.g, edge.b, 0.13 * frac + 0.05))
	draw_arc(centre, r, 0.0, TAU, 48, Color(edge.r, edge.g, edge.b, 0.55 + 0.35 * frac), 3.0, true)
