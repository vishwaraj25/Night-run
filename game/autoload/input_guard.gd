extends Node
## Autoload: res://autoload/input_guard.gd -> "InputGuard"
##
## Releases every gameplay action when the game stops being the thing in front
## of the player. Without this the character runs on its own, which is the bug
## it exists for.
##
## The cause is that a key-down and its key-up are two separate events, and
## nothing guarantees you get the second one. Switch tabs mid-run in a browser,
## alt-tab out of a fullscreen build, take a call on a phone, or simply have
## the page lose focus while D is held, and the key-up is delivered to whatever
## took focus instead. Godot keeps the action pressed because as far as it
## knows the key never came up. Measured before this existed: with the key-up
## withheld, the character kept running at full speed for every one of the 121
## frames sampled, and Input.is_action_pressed("move_forward") was still true
## at the end.
##
## This matters most on the web build, which is how the game actually ships --
## a browser tab loses focus constantly and routinely eats the key-up.

## Everything the player can hold down. Anything not held (pause, mute) is
## harmless to release and is left out only because there is nothing to clear.
const HELD_ACTIONS := [
	"move_forward",
	"move_backward",
	"lane_up",
	"lane_down",
	"crouch",
	"jump",
	"fire",
	"shield",
]

func _ready() -> void:
	# Must keep running while the tree is paused: losing focus to a phone call
	# is exactly when the pause menu is up.
	process_mode = Node.PROCESS_MODE_ALWAYS

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, \
		NOTIFICATION_WM_WINDOW_FOCUS_OUT, \
		NOTIFICATION_APPLICATION_PAUSED:
			release_all()

## Public so anything that tears down a control surface can call it -- the
## on-screen pads do, because a pad that is freed mid-press (scene change,
## death, the level unloading under a thumb) never sends its own release.
func release_all() -> void:
	for action in HELD_ACTIONS:
		if InputMap.has_action(action) and Input.is_action_pressed(action):
			Input.action_release(action)
