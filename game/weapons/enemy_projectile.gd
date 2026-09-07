extends Area2D
## Return fire from flyer squadrons. Mirrors projectile_base.gd but damages
## the player instead of enemies — the thing that makes a squadron
## encounter something you dodge, not just a stationary target gallery.
##
## A perfect-timed shield block deflects it: it reverses direction, switches
## to targeting enemies instead of the player, and keeps flying — a real
## parry, not just a bullet that vanishes.

@export var speed: float = 260.0
@export var damage: float = 8.0
@export var lifetime: float = 3.0

var _age: float = 0.0
var _deflected: bool = false
var _perfect: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	global_position += Vector2.RIGHT.rotated(global_rotation) * speed * delta
	_age += delta
	if _age > lifetime:
		queue_free()

func _on_body_entered(body: Node) -> void:
	if _deflected:
		if body.is_in_group("enemy") and body.has_method("take_damage"):
			body.take_damage(damage)
			queue_free()
		return

	if body.is_in_group("player") and body.has_method("take_damage"):
		var deflected: bool = body.take_damage(damage, self)
		if deflected:
			_deflect(body.get("last_block_perfect") == true)
		else:
			var spark := preload("res://fx/impact_spark.tscn").instantiate()
			spark.global_position = global_position
			spark.color = Color(1.0, 0.4, 0.35) # red for damage taken, gold for damage dealt
			get_tree().current_scene.add_child(spark)
			queue_free()

func _deflect(perfect: bool = false) -> void:
	_deflected = true
	_perfect = perfect
	global_rotation += PI
	collision_layer = 4  # now behaves like a player projectile
	collision_mask = 2   # -> detects the enemy layer instead of the player
	# A perfect deflect -- shield raised within its window rather than held --
	# sends the round back twice as fast for twice the damage. That is the
	# skill payoff; a late block still saves you but barely scratches.
	if perfect:
		speed *= 2.0
		damage *= 2.0
		_age = 0.0 # full lifetime again, so a fast return actually reaches
	else:
		damage *= 0.5
	queue_redraw()

func _draw() -> void:
	var body := Color(1.0, 0.95, 0.3) if _deflected else Color(1.0, 0.22, 0.28)
	if _perfect:
		body = Color(0.55, 1.0, 1.0) # perfect returns read cyan, not gold
	var core := Color(1.0, 1.0, 0.8) if _deflected else Color(1.0, 0.75, 0.7)
	draw_line(Vector2(-20, 0), Vector2(-5, 0), Color(body.r, body.g, body.b, 0.3), 4.0)
	draw_rect(Rect2(-9, -3.2, 18, 6.4), body)
	draw_rect(Rect2(-6, -1.6, 13, 3.2), core)
	draw_circle(Vector2(8, 0), 3.0, Color(1, 1, 1, 0.9))
