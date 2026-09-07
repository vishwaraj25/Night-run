extends CanvasLayer
## Status readout. Everything here is driven by signals rather than polled, so
## a bar can't drift out of sync with the thing it's reporting -- the two
## exceptions are score and coins, which live on GameState and have no signal.

@onready var health_bar: ProgressBar = $HealthBar
@onready var health_label: Label = $HealthLabel
@onready var weapon_bar: ProgressBar = $WeaponBar
@onready var weapon_label: Label = $WeaponLabel
@onready var shield_bar: ProgressBar = $ShieldBar
@onready var jetpack_bar: ProgressBar = $JetpackBar
@onready var score_label: Label = $ScoreLabel
@onready var coins_label: Label = $CoinsLabel
@onready var shield_label: Label = $ShieldLabel
@onready var pickup_label: Label = $PickupLabel
@onready var pickup_timer: Timer = $PickupTimer
@onready var boss_bar: ProgressBar = $BossBar
@onready var boss_label: Label = $BossLabel

func _ready() -> void:
	var car := get_tree().get_first_node_in_group("player")
	if car:
		car.health_changed.connect(_on_health_changed)
		car.shield_changed.connect(_on_shield_changed)
		if car.has_signal("jetpack_changed"):
			car.jetpack_changed.connect(_on_jetpack_changed)
		if car.has_signal("shield_energy_changed"):
			car.shield_energy_changed.connect(_on_shield_energy_changed)
		health_bar.max_value = car.max_health
		health_bar.value = car.health
		_set_health_text(car.health, car.max_health)

	shield_label.visible = false
	pickup_label.visible = false
	jetpack_bar.visible = false
	# The weapon bar only means something while a timed pickup is running --
	# the starting gun is permanent and an empty blue bar under it would read
	# as "about to lose it".
	weapon_bar.visible = false
	boss_bar.visible = false
	boss_label.visible = false

	EventBus.item_collected.connect(_on_item_collected)
	EventBus.checkpoint_reached.connect(_on_checkpoint_reached)
	EventBus.weapon_changed.connect(_on_weapon_changed)
	EventBus.weapon_timer_changed.connect(_on_weapon_timer_changed)
	EventBus.boss_engaged.connect(_on_boss_engaged)
	EventBus.boss_health_changed.connect(_on_boss_health_changed)
	EventBus.boss_phase_changed.connect(_on_boss_phase_changed)
	EventBus.boss_defeated.connect(_on_boss_defeated)
	pickup_timer.timeout.connect(func(): pickup_label.visible = false)

func _process(_delta: float) -> void:
	score_label.text = "Score: %d" % GameState.score
	coins_label.text = "Coins: %d" % GameState.coins

func _set_health_text(current: float, max_hp: float) -> void:
	health_label.text = "%d / %d" % [roundi(current), roundi(max_hp)]

func _on_health_changed(current: float, max_hp: float) -> void:
	health_bar.max_value = max_hp
	health_bar.value = current
	_set_health_text(current, max_hp)

func _on_shield_changed(active: bool) -> void:
	shield_label.visible = active

func _on_shield_energy_changed(current: float, max_energy: float) -> void:
	shield_bar.max_value = max_energy
	shield_bar.value = current

func _on_jetpack_changed(seconds_left: float, total: float) -> void:
	if seconds_left <= 0.0 or total <= 0.0:
		jetpack_bar.visible = false
		return
	jetpack_bar.max_value = total
	jetpack_bar.value = seconds_left
	jetpack_bar.visible = true

func _on_weapon_changed(weapon_name: String) -> void:
	weapon_label.text = weapon_name.replace("_", " ").to_upper()

func _on_weapon_timer_changed(seconds_left: float, total: float) -> void:
	if total <= 0.0:
		weapon_bar.visible = false
		return
	weapon_bar.max_value = total
	weapon_bar.value = seconds_left
	weapon_bar.visible = true

func _on_item_collected(item_name: String) -> void:
	pickup_label.text = "%s ACQUIRED" % item_name.replace("_", " ").to_upper()
	pickup_label.visible = true
	pickup_timer.start()

func _on_boss_engaged(boss: Node) -> void:
	boss_bar.max_value = boss.max_health
	boss_bar.value = boss.max_health
	boss_bar.visible = true
	boss_label.text = "MECH — PHASE 1"
	boss_label.visible = true

func _on_boss_health_changed(current: float, max_hp: float) -> void:
	boss_bar.max_value = max_hp
	boss_bar.value = current

func _on_boss_phase_changed(phase: int) -> void:
	boss_label.text = "MECH — PHASE %d" % phase

func _on_boss_defeated() -> void:
	boss_bar.visible = false
	boss_label.visible = false

func _on_checkpoint_reached(_pos: Vector2) -> void:
	pickup_label.text = "CHECKPOINT"
	pickup_label.visible = true
	pickup_timer.start()
