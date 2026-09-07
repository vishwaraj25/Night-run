extends Node
## Runs the boss encounter: seals the arena, spawns the boss, and opens the
## arena again once it dies. Kept separate from EnemySpawner so tuning "when
## does the level climax" never touches regular enemy pacing.
##
## Sealing matters for the fight to read as a fight. Before this the boss was
## just another enemy standing in an open corridor -- you could walk past it,
## or backpedal out of engage_range indefinitely and plink at it from safety.
## Now crossing the trigger drops a wall behind you and one at the far end of
## the arena, and they only lift when the mech is down.

@export var car_path: NodePath
@export var boss_scene: PackedScene
@export var trigger_distance: float = 6000.0

## Arena bounds in world x. The walls stand at these two lines; the boss is
## placed inside them rather than at a fixed offset from the player, so the
## fight always starts at the same spacing however fast you arrived.
@export var arena_left_x: float = 26750.0
@export var arena_right_x: float = 29000.0
@export var arena_floor_y: float = 500.0
@export var wall_height: float = 900.0

var _car: Node2D
var _spawned: bool = false
var _boss: Node2D
var _walls: Array[StaticBody2D] = []

func _ready() -> void:
	_car = get_node(car_path)
	EventBus.boss_defeated.connect(_open_arena)

func _process(_delta: float) -> void:
	if _spawned or _car.global_position.x < trigger_distance:
		return
	_spawned = true
	_clear_the_field()
	_seal_arena()
	_boss = boss_scene.instantiate()
	get_tree().current_scene.add_child(_boss)
	# Far side of the arena, facing back toward the door you came in through,
	# and dropped in from above rather than placed flush on the floor. The
	# platforms are one-way: they only separate a body approaching from above,
	# so a boss spawned exactly at arena_floor_y starts overlapping the slab
	# and falls straight through the arena and out of the world.
	# x=-450 put it directly over the arena's right-hand ledge (28350-28590),
	# so it landed on that instead of the floor and fought from 190px up.
	# -220 clears the ledge and still leaves its 343px-wide body inside the
	# right wall.
	_boss.global_position = Vector2(arena_right_x - 220.0, arena_floor_y - 200.0)
	# Half the mech's 343px body plus a margin, so its edges stay over floor.
	_boss.arena_min_x = arena_left_x + 200.0
	_boss.arena_max_x = arena_right_x - 200.0
	EventBus.boss_engaged.emit(_boss)

## The boss fight is its own encounter. Stop the level spawner and remove
## anything it still has alive, so a sentry that wandered in behind you can't
## be shooting you in the back through a scripted fight. The boss's own
## phase-3 adds are in "boss_add", not "spawned_enemy", so they are untouched.
func _clear_the_field() -> void:
	var spawner := get_parent().get_node_or_null("EnemySpawner")
	if spawner:
		spawner.set_process(false)
	for e in get_tree().get_nodes_in_group("spawned_enemy"):
		if is_instance_valid(e):
			e.queue_free()

func _seal_arena() -> void:
	for x in [arena_left_x, arena_right_x]:
		var wall := StaticBody2D.new()
		# Layer 16 is the terrain layer level_builder.gd puts platforms on, and
		# what the player masks. Layer 1 (the obvious guess) is invisible to it:
		# the test run walked straight through the wall and off the end of the
		# level, dying repeatedly in the void past x=29050.
		wall.collision_layer = 16
		wall.collision_mask = 0
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(40.0, wall_height)
		shape.shape = rect
		wall.add_child(shape)
		wall.global_position = Vector2(x, arena_floor_y - wall_height * 0.5)
		get_tree().current_scene.add_child(wall)
		_walls.append(wall)

## Tear the encounter down so it can start again from the top. Called when the
## player dies in the arena: they respawn at the boss-door checkpoint and walk
## back in to a full-health boss, rather than resuming against one they had
## already whittled down across several deaths.
func restart_encounter() -> void:
	if not _spawned:
		return
	if is_instance_valid(_boss):
		_boss.queue_free()
	_boss = null
	_open_arena()
	_spawned = false

func _open_arena() -> void:
	for w in _walls:
		if is_instance_valid(w):
			w.queue_free()
	_walls.clear()
