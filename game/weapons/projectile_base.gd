extends Area2D
## Bullet that flies in whatever direction it was fired (global_rotation is
## set by the weapon at spawn time, following the mouse-aimed gun), not
## always straight right. Placeholder visual is a drawn rectangle so no
## texture asset is required yet.

@export var speed: float = 850.0
@export var damage: float = 10.0
@export var lifetime: float = 2.0
@export var impact_spark_scene: PackedScene = preload("res://fx/impact_spark.tscn")

var _age: float = 0.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	global_position += Vector2.RIGHT.rotated(global_rotation) * speed * delta
	_age += delta
	if _age > lifetime:
		queue_free()

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("enemy") and body.has_method("take_damage"):
		body.take_damage(damage)
		Audio.play("hit_enemy")
		_spawn_spark()
		queue_free()

func _spawn_spark() -> void:
	if not impact_spark_scene:
		return
	var spark := impact_spark_scene.instantiate()
	spark.max_radius = 26.0 # up from the 16 default: at 16 a hit was easy to miss in a busy frame
	get_tree().current_scene.add_child(spark)
	spark.global_position = global_position

func _draw() -> void:
	# Trail first so the round sits on top of it.
	draw_line(Vector2(-22, 0), Vector2(-6, 0), Color(1.0, 0.8, 0.25, 0.35), 4.0)
	draw_rect(Rect2(-10, -3.5, 20, 7), Color(1.0, 0.72, 0.15))
	draw_rect(Rect2(-7, -1.8, 15, 3.6), Color(1.0, 0.98, 0.7))
	draw_circle(Vector2(9, 0), 3.4, Color(1, 1, 1, 0.95))
