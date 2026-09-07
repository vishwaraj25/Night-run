extends StaticBody2D
## Stationary destructible turret — used for both the "turret" and "bot"
## skins from Traps.png (same behavior, different art/scale). Unlike the
## mobile enemies, this never moves: it just tracks the player horizontally
## and fires when they're in range and roughly level with it. Has its own
## idle/fire/dead textures (three separate image files, not a spritesheet —
## swapped directly via `sprite.texture` rather than a frame index).

const HitFeedback = preload("res://fx/hit_feedback.gd")
const Explosion = preload("res://fx/explosion.gd")

@export var max_health: float = 40.0
@export var fire_rate: float = 0.9
@export var fire_range: float = 500.0
@export var y_tolerance: float = 60.0 # only fires at a player roughly level with it
@export var projectile_scene: PackedScene
@export var idle_texture: Texture2D
@export var fire_texture: Texture2D
@export var dead_texture: Texture2D
@export var fire_pose_time: float = 0.2
@export var telegraph_time: float = 0.4 # red wind-up before the shot, so it's dodgeable on sight
@export var health_bar_height: float = 150.0 # traps are placed at wildly different scales, so this is per-instance

var health: float
var _fire_cooldown: float = 0.0
var _fire_pose_timer: float = 0.0
var _dead: bool = false
var _dead_timer: float = 0.0

@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	health = max_health
	add_to_group("enemy")
	sprite.texture = idle_texture
	_fire_cooldown = randf_range(0.0, fire_rate)

func _physics_process(delta: float) -> void:
	if _dead:
		_dead_timer += delta
		if _dead_timer > 2.5:
			queue_free()
		return

	var player := get_tree().get_first_node_in_group("player")
	var engaged := false
	if player:
		var to_player: Vector2 = player.global_position - global_position
		if absf(to_player.y) <= y_tolerance and to_player.length() <= fire_range:
			engaged = true
			_fire_cooldown -= delta
			# Ramp a red tint over the last telegraph_time before firing.
			if _fire_cooldown < telegraph_time:
				HitFeedback.set_telegraph(sprite, 1.0 - (_fire_cooldown / telegraph_time))
			else:
				HitFeedback.set_telegraph(sprite, 0.0)
			if _fire_cooldown <= 0.0:
				_fire_at(player)
				_fire_cooldown = fire_rate
				HitFeedback.set_telegraph(sprite, 0.0)
	if not engaged:
		HitFeedback.set_telegraph(sprite, 0.0)

	if _fire_pose_timer > 0.0:
		_fire_pose_timer -= delta
		sprite.texture = fire_texture
		if _fire_pose_timer <= 0.0:
			sprite.texture = idle_texture

func _fire_at(player: Node2D) -> void:
	if not projectile_scene:
		return
	var proj := projectile_scene.instantiate()
	proj.global_position = global_position
	proj.global_rotation = (player.global_position - global_position).angle()
	get_tree().current_scene.add_child(proj)
	Audio.play("enemy_shoot")
	_fire_pose_timer = fire_pose_time

func take_damage(amount: float, _source: Node = null) -> bool:
	if _dead:
		return false
	health -= amount
	HitFeedback.flash_hit(sprite)
	queue_redraw()
	if health <= 0.0:
		_dead = true
		_dead_timer = 0.0
		sprite.texture = dead_texture
		HitFeedback.set_telegraph(sprite, 0.0)
		Explosion.spawn(self, global_position + Vector2(0, -60), 85.0)
		EventBus.enemy_defeated.emit("trap_shooter", global_position)
	return false

## Same "only once damaged" bar as enemy_base.gd -- duplicated rather than
## shared because this is a StaticBody2D and can't inherit from it.
func _draw() -> void:
	if _dead or health >= max_health or health <= 0.0:
		return
	var w := 44.0
	var h := 5.0
	var y := -health_bar_height
	var frac: float = clampf(health / max_health, 0.0, 1.0)
	draw_rect(Rect2(-w * 0.5, y, w, h), Color(0, 0, 0, 0.65))
	draw_rect(Rect2(-w * 0.5, y, w * frac, h), Color(1.0, 0.3, 0.3, 0.95))
