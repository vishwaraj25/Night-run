extends Area2D
## Floor panel that cycles retracted (safe to stand/walk on) and extended
## (spiked, damages on contact). Damage applies once per extension, not
## continuously, so standing on top the instant it retracts and walking off
## doesn't rack up repeated hits from one cycle.

@export var retracted_time: float = 1.6
@export var extended_time: float = 1.0
@export var damage: float = 20.0
@export var retracted_texture: Texture2D
@export var extended_texture: Texture2D

var _extended: bool = false
var _timer: float = 0.0
var _hit_this_cycle: bool = false

@onready var sprite: Sprite2D = $Sprite2D
@onready var collider: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	_timer = retracted_time
	_apply_state()
	body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_extended = not _extended
		_timer = extended_time if _extended else retracted_time
		_hit_this_cycle = false
		_apply_state()

func _apply_state() -> void:
	sprite.texture = extended_texture if _extended else retracted_texture
	# bottom-align: the two textures are different heights (spikes add height
	# above the base plate), so center-anchoring would shift the plate itself
	# up/down between states instead of just growing the spikes upward from a
	# fixed floor line.
	sprite.position.y = -sprite.texture.get_height() * sprite.scale.y
	collider.disabled = not _extended

func _on_body_entered(body: Node) -> void:
	if _extended and not _hit_this_cycle and body.is_in_group("player") and body.has_method("take_damage"):
		_hit_this_cycle = true
		body.take_damage(damage, self)
