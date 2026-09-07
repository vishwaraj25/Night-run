extends CharacterBody2D
## Shared behavior for ground enemies: falls under gravity onto whatever
## platform is beneath it, drives left toward the player, takes damage,
## dies into score + telemetry. Bosses extend this and override die().
##
## Previously these chased a computed terrain height every frame; now they
## just collide with the real platforms like the player does, so they stand
## on ledges, walk off edges, and fall — no special-casing needed.
## enemy_flyer.gd overrides _physics_process entirely and ignores gravity.

@export var enemy_name: String = "drone"
@export var max_health: float = 30.0
@export var move_speed: float = 90.0
@export var contact_damage: float = 15.0
@export var gravity: float = 1400.0
@export var enemy_projectile_scene: PackedScene # leave empty for a melee-only enemy
@export var fire_rate: float = 1.1
@export var fire_range: float = 500.0
## Where the barrel actually is, measured off the fire-frame's muzzle flash in
## the sprite sheet, in body-local pixels for the art's default (right-facing)
## pose. Shots used to spawn at global_position -- the enemy's feet or belly --
## so nothing looked like it came out of a gun. Mirrored automatically when
## the sprite is flipped.
@export var muzzle_offset: Vector2 = Vector2.ZERO
## Anything that ends up below this is gone -- knocked off a ledge, spawned
## over a gap, whatever. Without it they fall forever, still counting against
## the spawner's budget until the player has run 1500px further on.
@export var fall_death_y: float = 1100.0

@export var health_bar_height: float = 120.0 # how far above the origin the bar floats; per-enemy since they're wildly different sizes
@export var health_bar_width: float = 48.0

var health: float
var _fire_cooldown: float = 0.0

## Only shown once something has actually been damaged -- a bar over every
## full-health enemy is just clutter, but without one you can't tell whether
## a tough enemy is nearly dead or you've barely scratched it.
func _draw() -> void:
	if health_bar_width <= 0.0 or health >= max_health or health <= 0.0:
		return # width 0 opts an enemy out entirely (the boss uses the HUD bar)
	var w := health_bar_width
	var h := 5.0
	var y := -health_bar_height
	var frac: float = clampf(health / max_health, 0.0, 1.0)
	draw_rect(Rect2(-w * 0.5, y, w, h), Color(0, 0, 0, 0.65))
	draw_rect(Rect2(-w * 0.5, y, w * frac, h), Color(1.0, 0.3, 0.3, 0.95))

func _ready() -> void:
	health = max_health
	add_to_group("enemy")

func _physics_process(delta: float) -> void:
	if global_position.y > fall_death_y:
		queue_free() # no score, no death animation: it didn't die, it left
		return
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y += gravity * delta
	velocity.x = -move_speed
	move_and_slide()

	for i in get_slide_collision_count():
		var collision := get_slide_collision(i)
		var other := collision.get_collider()
		if other and other.is_in_group("player") and other.has_method("take_damage"):
			other.take_damage(contact_damage, self) # self as source -> a perfect block counter-hits us

	if enemy_projectile_scene:
		_fire_cooldown = max(0.0, _fire_cooldown - delta)
		if _fire_cooldown <= 0.0:
			_try_fire_at_player()

func _try_fire_at_player() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if not player or global_position.distance_to(player.global_position) > fire_range:
		return
	var muzzle := get_muzzle_position()
	var proj := enemy_projectile_scene.instantiate()
	proj.global_position = muzzle
	proj.global_rotation = (player.global_position - muzzle).angle()
	get_tree().current_scene.add_child(proj)
	Audio.play("enemy_shoot")
	_fire_cooldown = fire_rate

## Muzzle in world space, mirrored when the sprite is facing left. Subclasses
## with a $Sprite2D get the flip for free; anything without one fires from the
## unmirrored offset.
func get_muzzle_position() -> Vector2:
	var offset := muzzle_offset
	var spr := get_node_or_null("Sprite2D")
	if spr and spr.flip_h:
		offset.x = -offset.x
	return global_position + offset

func take_damage(amount: float) -> void:
	health -= amount
	if health <= 0.0:
		die()

func die() -> void:
	EventBus.enemy_defeated.emit(enemy_name, global_position)
	queue_free()
