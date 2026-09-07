extends Camera2D
## Look-ahead camera: instead of only ever framing the car's own height, it
## checks what's coming up over the next lookahead_distance (via
## LevelBuilder.get_vertical_extent_ahead) and both nudges the view toward
## the middle of that range and zooms out when it's wide — so a fork with
## a route above or below is visible before you reach it, not a surprise
## you fall into. Found via group lookup, not a NodePath, so this scene
## doesn't have to know which level it's sitting in.

@export var lookahead_distance: float = 700.0
@export var zoomed_in: float = 0.85       # normal, single-route stretches
@export var zoomed_out: float = 0.6       # wide forks — bigger vertical spread visible
@export var wide_spread_px: float = 500.0 # spread at/above this maps to fully zoomed_out
@export var vertical_follow_speed: float = 2.5
@export var zoom_follow_speed: float = 2.5
@export var max_vertical_bias: float = 160.0 # cap how far the view shifts from the car itself

var _platforms: Node = null
var _current_zoom: float = 0.85
var _current_vertical_bias: float = 0.0

func _ready() -> void:
	_current_zoom = zoomed_in
	zoom = Vector2(_current_zoom, _current_zoom)

func _physics_process(delta: float) -> void:
	if not is_instance_valid(_platforms):
		_platforms = get_tree().get_first_node_in_group("level_platforms")
		if not _platforms:
			return

	var car_x: float = get_parent().global_position.x
	var car_y: float = get_parent().global_position.y
	var extent: Vector2 = _platforms.get_vertical_extent_ahead(car_x, lookahead_distance)
	if extent == Vector2.ZERO:
		return

	var spread: float = extent.y - extent.x
	var mid_y: float = (extent.x + extent.y) * 0.5
	var desired_bias: float = clamp(mid_y - car_y, -max_vertical_bias, max_vertical_bias)
	_current_vertical_bias = lerp(_current_vertical_bias, desired_bias, delta * vertical_follow_speed)
	offset.y = _current_vertical_bias

	var desired_zoom: float = lerp(zoomed_in, zoomed_out, clamp(spread / wide_spread_px, 0.0, 1.0))
	_current_zoom = lerp(_current_zoom, desired_zoom, delta * zoom_follow_speed)
	zoom = Vector2(_current_zoom, _current_zoom)
