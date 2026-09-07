extends Node
## Spawns one enemy at a time at hand-placed positions along the level.
##
## spawn_ahead_distance was 500, which was the bug behind "they appear out
## of nowhere in front of me": the viewport is 960 wide and the camera sits
## at car.x + 200, so the right edge of the screen is car.x + 680 — a
## spawn at +500 was landing ~180px INSIDE the visible screen. At 1000 they
## always walk in from well offscreen.
##
## Encounters also carry their own y, and one whose y is far from the
## player's is skipped: with three routes stacked at the same x, otherwise
## the enemies on routes you didn't take would silently eat the max_alive
## budget and starve the route you're actually on.

@export var car_path: NodePath
@export var ground_enemy_scenes: Array[PackedScene] = []
@export var air_enemy_scenes: Array[PackedScene] = []
@export var spawn_ahead_distance: float = 1000.0
@export var route_y_tolerance: float = 150.0 # skip encounters belonging to another tier (fork 2's are 280 apart)
@export var max_alive: int = 6
@export var despawn_behind_distance: float = 1500.0 ## see _cull_stragglers()

# {x, y, kind}. Grouped by section and tier for readability; _ready() sorts a
# working copy by x, which is what the spawner actually walks.
#
# It has to, and this was a real bug: the list is grouped by tier, so it runs
# 13400 .. 17000 on the high tier and then jumps BACK to 13500 for the mid
# tier. The spawner advances one index at a time and only waits when the next
# entry is still ahead of the player -- so once you passed x=17000, every
# remaining mid- and low-tier entry was already "behind" and fired instantly,
# spawning a whole tier's worth of enemies 3500px back where they were culled
# without ever being seen. Two thirds of fork 2's encounters never reached the
# player, and adding more entries to those tiers changed nothing at all.
const ENCOUNTER_TIMELINE := [
	# --- street ---
	{"x": 1000.0, "y": 440.0, "kind": "ground"},
	{"x": 1600.0, "y": 300.0, "kind": "air"},
	{"x": 2100.0, "y": 440.0, "kind": "ground"},
	{"x": 2700.0, "y": 440.0, "kind": "ground"},
	{"x": 3300.0, "y": 440.0, "kind": "ground"},
	{"x": 3600.0, "y": 280.0, "kind": "air"},
	# --- fork 1: high road ---
	{"x": 4600.0, "y": 440.0, "kind": "ground"}, # fills the 3.6s hole at the fork mouth
	{"x": 4900.0, "y": 360.0, "kind": "ground"},
	{"x": 5500.0, "y": 280.0, "kind": "ground"},
	{"x": 6100.0, "y": 180.0, "kind": "air"},
	{"x": 6700.0, "y": 280.0, "kind": "ground"},
	# --- fork 1: underpass ---
	{"x": 5100.0, "y": 640.0, "kind": "ground"},
	{"x": 5900.0, "y": 640.0, "kind": "ground"},
	{"x": 6800.0, "y": 640.0, "kind": "ground"},
	# --- rejoin + speed track ---
	{"x": 8800.0, "y": 440.0, "kind": "ground"},
	{"x": 9300.0, "y": 300.0, "kind": "air"},
	{"x": 10000.0, "y": 440.0, "kind": "ground"},
	{"x": 10500.0, "y": 440.0, "kind": "ground"},
	{"x": 10800.0, "y": 300.0, "kind": "air"},
	{"x": 11400.0, "y": 440.0, "kind": "ground"},
	{"x": 12000.0, "y": 440.0, "kind": "ground"},
	{"x": 12600.0, "y": 280.0, "kind": "air"},
	# --- fork 2: high tier ---
	{"x": 13400.0, "y": 340.0, "kind": "ground"},
	{"x": 14100.0, "y": 340.0, "kind": "ground"}, # 7.8s hole at x=13541, high tier
	{"x": 14400.0, "y": 220.0, "kind": "air"},
	{"x": 14700.0, "y": 340.0, "kind": "ground"},
	{"x": 16300.0, "y": 220.0, "kind": "air"},
	{"x": 17000.0, "y": 340.0, "kind": "ground"},
	# --- fork 2: mid tier ---
	{"x": 13500.0, "y": 620.0, "kind": "ground"},
	{"x": 14200.0, "y": 620.0, "kind": "ground"}, # same hole, mid tier
	{"x": 15000.0, "y": 620.0, "kind": "ground"},
	{"x": 16700.0, "y": 620.0, "kind": "ground"},
	{"x": 17600.0, "y": 620.0, "kind": "ground"},
	# --- fork 2: low tier ---
	{"x": 13600.0, "y": 900.0, "kind": "ground"},
	{"x": 14300.0, "y": 900.0, "kind": "ground"}, # same hole, low tier
	{"x": 15400.0, "y": 900.0, "kind": "ground"},
	{"x": 16400.0, "y": 900.0, "kind": "ground"},
	# --- rejoin ---
	{"x": 19000.0, "y": 440.0, "kind": "ground"},
	{"x": 19400.0, "y": 440.0, "kind": "ground"},
	{"x": 19600.0, "y": 300.0, "kind": "air"},
	{"x": 19900.0, "y": 440.0, "kind": "ground"}, # fills a measured 6s lull before the tower
	{"x": 20100.0, "y": 280.0, "kind": "air"},
	# --- vertical tower ---
	{"x": 20900.0, "y": 280.0, "kind": "ground"},
	{"x": 21500.0, "y": 200.0, "kind": "ground"},
	{"x": 22000.0, "y": 200.0, "kind": "ground"},
	{"x": 22050.0, "y": 260.0, "kind": "ground"}, # 9.8s hole at x=22345: this is
	{"x": 22400.0, "y": 180.0, "kind": "air"},    # the 400px jump across the tower,
	{"x": 22600.0, "y": 340.0, "kind": "ground"}, # so pressure goes either side of it
	{"x": 22700.0, "y": 280.0, "kind": "ground"},
	{"x": 23300.0, "y": 380.0, "kind": "ground"},
	{"x": 23800.0, "y": 340.0, "kind": "air"},
	# --- approach to the gear chamber: the last stretch, so this is the
	# densest ground+air mix in the level -- the difficulty curve's peak
	# before the boss door ---
	{"x": 24400.0, "y": 440.0, "kind": "ground"},
	{"x": 24700.0, "y": 440.0, "kind": "ground"},
	{"x": 25300.0, "y": 250.0, "kind": "air"},
	{"x": 25900.0, "y": 440.0, "kind": "ground"},
	{"x": 26200.0, "y": 300.0, "kind": "air"},
	{"x": 26400.0, "y": 440.0, "kind": "ground"},
]

var _car: Node2D
var _next_index: int = 0
var _timeline: Array = []

func _ready() -> void:
	_car = get_node(car_path)
	_timeline = ENCOUNTER_TIMELINE.duplicate()
	_timeline.sort_custom(func(a, b): return a["x"] < b["x"])

func _process(_delta: float) -> void:
	_cull_stragglers()
	if _next_index >= _timeline.size():
		return
	var next: Dictionary = _timeline[_next_index]
	if _car.global_position.x + spawn_ahead_distance < next["x"]:
		return

	# On another tier entirely -> consume it without spawning, so it doesn't
	# block or crowd out the route the player actually took.
	#
	# Ground only. Air encounters are deliberately 200px above the player's
	# head, so they fail any tolerance tight enough to separate fork 2's tiers
	# -- tightening this from 260 to 150 silently filtered out more than half
	# the drones in the level.
	if next["kind"] != "air" and absf(_car.global_position.y - next["y"]) > route_y_tolerance:
		_next_index += 1
		return

	# Count only what this spawner put there. Static traps (turrets/bots) are
	# also in "enemy" so player bullets can damage them -- counting those here
	# meant the 4 placed trap shooters saturated max_alive at level load and
	# NO mobile enemy ever spawned for the whole level.
	if get_tree().get_nodes_in_group("spawned_enemy").size() >= max_alive:
		return # too crowded; try again next frame rather than skipping the wave

	_spawn_one(next["x"], next["y"], next["kind"])
	_next_index += 1

## Nothing used to remove an enemy the player had run past. Flyers travel
## left and grunts get stuck on geometry, so after the first few encounters
## four abandoned enemies sat off-screen forever, permanently holding
## max_alive at its cap -- a full playthrough spawned 5 enemies total and the
## whole back half of the level was empty. Anything this far behind the
## player (or fallen out of the world) is gone for good, so free it.
func _cull_stragglers() -> void:
	for e in get_tree().get_nodes_in_group("spawned_enemy"):
		if not is_instance_valid(e):
			continue
		if _car.global_position.x - e.global_position.x > despawn_behind_distance \
				or e.global_position.y > 2000.0:
			e.queue_free()

## World y of the first terrain surface at or below `from`, searching a band
## around the encounter's nominal height. INF when there's nothing there.
func _surface_below(from: Vector2) -> float:
	var space := _car.get_world_2d().direct_space_state
	var q := PhysicsRayQueryParameters2D.create(from - Vector2(0, 150.0), from + Vector2(0, 400.0))
	q.collision_mask = 16 # terrain, same layer level_builder.gd builds on
	var hit := space.intersect_ray(q)
	return hit["position"].y if hit.has("position") else INF

func _spawn_one(x: float, y: float, kind: String) -> void:
	var pool: Array[PackedScene] = air_enemy_scenes if kind == "air" else ground_enemy_scenes
	if pool.is_empty():
		return
	var scene: PackedScene = pool[randi() % pool.size()]
	var spawn := Vector2(x, y)
	if kind != "air":
		# Put ground enemies on actual ground. The timeline carries a nominal y
		# per encounter, but the platform under that x depends on which route
		# the level builder laid there -- a spawn over a gap dropped the enemy
		# straight out of the world, which is most of why enemies kept
		# disappearing. Skip the encounter entirely rather than spawn into air.
		var surface := _surface_below(spawn)
		if surface == INF:
			return
		spawn.y = surface - 40.0 # drop in from above; 4px is inside a one-way slab's tolerance
	var enemy := scene.instantiate()
	enemy.global_position = spawn
	enemy.add_to_group("spawned_enemy") # what max_alive actually counts
	get_tree().current_scene.add_child(enemy)
