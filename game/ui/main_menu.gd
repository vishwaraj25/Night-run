extends Control

@onready var play_button: Button = $PlayButton
@onready var controls_button: Button = $ControlsButton
@onready var quit_button: Button = $QuitButton
@onready var controls_panel: Panel = $ControlsPanel
@onready var close_button: Button = $ControlsPanel/CloseButton

func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)
	controls_button.pressed.connect(_on_controls_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	close_button.pressed.connect(_on_close_controls_pressed)

func _on_play_pressed() -> void:
	Audio.play("menu_click")
	Telemetry.log_event("menu_click", {"button": "play"})
	get_tree().change_scene_to_file("res://world/level.tscn")

func _on_controls_pressed() -> void:
	Audio.play("menu_click")
	Telemetry.log_event("menu_click", {"button": "controls"})
	controls_panel.visible = true

func _on_close_controls_pressed() -> void:
	Audio.play("menu_click")
	Telemetry.log_event("menu_click", {"button": "close_controls"})
	controls_panel.visible = false

func _on_quit_pressed() -> void:
	Audio.play("menu_click")
	Telemetry.log_event("menu_click", {"button": "quit"})
	get_tree().quit()
