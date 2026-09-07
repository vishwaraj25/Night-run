extends Node2D
## Builds the playable area out of real solid platforms (StaticBody2D +
## RectangleShape2D, drawn with plain Polygon2D fills — no textures).
##
## LEVEL DESIGN lives in PLATFORMS below. Each entry is the platform's left
## edge x, its TOP surface y, width, and which route it belongs to. Route
## only affects tint, but the tint is functional: at a glance you can tell
## which tier you're standing on when two routes run at the same x.
##
## Everything is authored against the car's actual jump envelope:
##   single jump  = 97px rise, 193px of horizontal travel
##   double jump  = ~193px rise (second press timed near the apex)
## So gaps stay at 150px and climbs at 80px, except where a bigger climb is
## a deliberate skill gate (see FORK 2's high road, a 120px climb that
## requires a well-timed double jump).

## Was 40, chosen when the player was the 60px-tall car. Every stacked tier
## in the level pays this twice over, and the humanoid is 150 tall.
const THICKNESS := 26.0

# route -> [fill, top-lip]
const ROUTE_COLORS := {
	"main":  [Color(0.13, 0.14, 0.20), Color(0.35, 0.85, 0.95)],
	"high":  [Color(0.15, 0.16, 0.27), Color(0.45, 0.75, 1.00)],
	"low":   [Color(0.17, 0.12, 0.21), Color(0.85, 0.45, 0.95)],
	"arena": [Color(0.21, 0.16, 0.12), Color(1.00, 0.65, 0.20)],
}

const PLATFORMS: Array = [
	# ============ 1. STREET — intro, learn to drive/jump/shoot ============
	{"x": 0, "y": 500, "w": 1600, "route": "main"},
	{"x": 1750, "y": 500, "w": 500, "route": "main"},
	{"x": 2400, "y": 500, "w": 450, "route": "main"},
	{"x": 3000, "y": 500, "w": 900, "route": "main"},
	# Floating ledges. The street, the speed track and the approach were all
	# long flat runs with nothing to do vertically; these give the jump button
	# a purpose there and somewhere to break line of sight from a shooter.
	{"x": 1150, "y": 315, "w": 220, "route": "high"},
	{"x": 2450, "y": 315, "w": 240, "route": "high"},

	# ============ 2. FORK 1 — jump at the edge for the high road,
	# or just drive off it and fall into the underpass ============
	# HIGH: rooftops
	{"x": 4050, "y": 420, "w": 500, "route": "high"},
	{"x": 4700, "y": 420, "w": 450, "route": "high"},
	{"x": 5300, "y": 340, "w": 500, "route": "high"},
	{"x": 5950, "y": 340, "w": 450, "route": "high"},
	{"x": 6550, "y": 340, "w": 500, "route": "high"},
	{"x": 7200, "y": 420, "w": 450, "route": "high"},
	{"x": 7800, "y": 500, "w": 500, "route": "high"},
	# LOW: underpass. Starts flush under the ledge edge (x=3900) on purpose —
	# a 200px fall only carries you ~139px forward, so a platform starting
	# further out would drop you straight past it into the void.
	{"x": 3900, "y": 700, "w": 900, "route": "low"},
	{"x": 4950, "y": 700, "w": 600, "route": "low"},
	{"x": 5700, "y": 700, "w": 650, "route": "low"},
	{"x": 6500, "y": 700, "w": 700, "route": "low"},
	{"x": 7350, "y": 620, "w": 450, "route": "low"}, # exits via a ramp into the next step, see RAMPS
	{"x": 8000, "y": 500, "w": 450, "route": "low"},
	# both routes rejoin
	{"x": 8450, "y": 500, "w": 1000, "route": "main"},

	# ============ 3. SPEED TRACK — long, gap-free, boost pads go here ============
	{"x": 9600, "y": 500, "w": 1800, "route": "main"},
	{"x": 11550, "y": 500, "w": 1450, "route": "main"},
	{"x": 10150, "y": 315, "w": 240, "route": "high"},
	{"x": 10900, "y": 315, "w": 220, "route": "high"},
	{"x": 12100, "y": 315, "w": 240, "route": "high"},

	# ============ 4. FORK 2 — three tiers running in parallel ============
	# HIGH: 120px climb off the edge — a deliberate double-jump skill gate
	{"x": 13150, "y": 340, "w": 600, "route": "high"},
	{"x": 13900, "y": 340, "w": 550, "route": "high"},
	{"x": 14600, "y": 340, "w": 600, "route": "high"},
	{"x": 15350, "y": 340, "w": 550, "route": "high"},
	{"x": 16050, "y": 340, "w": 600, "route": "high"},
	{"x": 16800, "y": 340, "w": 600, "route": "high"},
	# runs flat all the way to the merge, then drops via a ramp (see RAMPS) —
	# used to end in its own separate step here, which put its underside only
	# 20-60px above MID/LOW's own final steps (less than the car's 60px
	# height — the three routes were literally clipping into each other).
	{"x": 17550, "y": 340, "w": 900, "route": "high"},
	# MID: the default — walk off the edge and step straight down onto it.
	# Flush with the ledge (x=13000) for the same reason as fork 1's underpass.
	{"x": 13000, "y": 620, "w": 900, "route": "main"},
	{"x": 14050, "y": 620, "w": 650, "route": "main"},
	{"x": 14850, "y": 620, "w": 700, "route": "main"},
	{"x": 15700, "y": 620, "w": 650, "route": "main"},
	{"x": 16500, "y": 620, "w": 650, "route": "main"},
	# extended flat, then a ramp into the merge (see RAMPS) — same clipping
	# reason as HIGH above.
	{"x": 17300, "y": 620, "w": 1000, "route": "main"},
	# LOW: drop through one of MID's gaps. One-way (200px back up beats a
	# double jump), so it climbs back out via two long, gentle ramps (see
	# RAMPS) instead of the three cramped steps this used to be — those put
	# LOW only 20-80px under MID/HIGH above it, well under the 60px the car
	# needs just to not clip into the platform overhead.
	{"x": 13300, "y": 900, "w": 800, "route": "low"},
	{"x": 14250, "y": 900, "w": 750, "route": "low"},
	{"x": 15150, "y": 900, "w": 800, "route": "low"},
	{"x": 16100, "y": 900, "w": 700, "route": "low"},
	# all three rejoin
	{"x": 18550, "y": 500, "w": 1500, "route": "main"},

	# ============ 5. VERTICAL — climb the tower, then descend ============
	{"x": 20200, "y": 420, "w": 400, "route": "main"},
	{"x": 20750, "y": 340, "w": 400, "route": "main"}, # ramp up from the previous platform, see RAMPS
	{"x": 21300, "y": 260, "w": 400, "route": "main"}, # ramp up from the previous platform, see RAMPS
	{"x": 21850, "y": 260, "w": 500, "route": "main"},
	{"x": 22500, "y": 340, "w": 450, "route": "main"}, # ramp down from the previous platform, see RAMPS
	{"x": 23100, "y": 440, "w": 450, "route": "main"},
	{"x": 23700, "y": 520, "w": 500, "route": "main"},

	# ============ 6. APPROACH ============
	{"x": 24350, "y": 500, "w": 900, "route": "main"},
	{"x": 25400, "y": 500, "w": 1100, "route": "main"},
	{"x": 24750, "y": 315, "w": 240, "route": "high"},
	{"x": 25900, "y": 315, "w": 260, "route": "high"},

	# ============ 7. GEAR CHAMBER — the boss arena (gears come later) ============
	{"x": 26650, "y": 500, "w": 2400, "route": "arena"},
	# Ledges over the arena floor, so the rocket volley is dodgeable. They sit
	# at 310 rather than the 410/320 they were: 410 is only a 90px rise, which
	# left 64px of headroom under a 150px character -- a low ceiling right
	# across the fighting floor. 310 is inside the 193px double-jump apex and
	# leaves 164px to walk under.
	{"x": 27050, "y": 310, "w": 240, "route": "arena"},
	{"x": 27700, "y": 310, "w": 260, "route": "arena"},
	{"x": 28350, "y": 310, "w": 240, "route": "arena"},
]

# Sloped connective platforms — a StaticBody2D with an angled collision
# shape, not a stepped jump. Used wherever two tiles are close enough in x/y
# that a smooth incline reads better than a floating step, and (critically)
# at every point where two routes converge to the same height, so the climb
# is spread across enough distance to never pinch a route from above.
# Each entry: x0,y0 = top of the slope, x1,y1 = bottom. Keep rise/run at or
# under ~40° (Godot's default floor_max_angle is 45°) so the car just drives
# up it — no jump needed.
const RAMPS: Array = [
	# Fork 1 — low route's final exit, smoothing what used to be a bare jump.
	{"x0": 7800, "y0": 620, "x1": 8000, "y1": 500, "route": "low"},
	# Fork 2 — the three-way convergence. LOW gets a long, gentle pre-climb
	# while MID is still flat and far above (huge headroom to spend), then
	# a short final rise; MID and HIGH each get a short final drop. All four
	# land at the same point (18650, 500), which is the merge platform.
	# LOW climbs out onto MID's tier at x=17150, which is the right-hand edge
	# of one of MID's platforms with a 150px gap after it -- so you arrive on
	# the mid route and jump the gap like anyone who took it, rather than
	# running a second ramp alongside theirs.
	{"x0": 16700, "y0": 900, "x1": 17150, "y1": 620, "route": "low"},
	# MID is the only route that ramps into the merge. HIGH just ends at
	# x=18450 and drops the 160px onto it -- a 0.48s fall carries you 124px, so
	# you land at ~18574, comfortably onto the merge platform at 18550.
	{"x0": 18300, "y0": 620, "x1": 18550, "y1": 500, "route": "main"},
	# Tower — a couple of climbs/descents turned into slopes for variety;
	# the rest stay as jumps so the climb still has rhythm.
	{"x0": 20600, "y0": 420, "x1": 20750, "y1": 340, "route": "main"},
	{"x0": 21150, "y0": 340, "x1": 21300, "y1": 260, "route": "main"},
	{"x0": 22350, "y0": 260, "x1": 22500, "y1": 340, "route": "main"},
]

# Named x-ranges, purely for the backdrop panels below — one solid "wall"
# per section so the whole stretch reads as one place instead of empty
# space with planks floating in it.
const SECTIONS: Array = [
	{"name": "street",  "x_start": -200,  "x_end": 3900},
	{"name": "fork1",   "x_start": 3900,  "x_end": 8450},
	{"name": "speed",   "x_start": 8450,  "x_end": 13000},
	{"name": "fork2",   "x_start": 13000, "x_end": 18650},
	{"name": "tower",   "x_start": 18650, "x_end": 24350},
	{"name": "approach","x_start": 24350, "x_end": 26650},
	{"name": "arena",   "x_start": 26650, "x_end": 29250},
]

const BACKDROP_COLOR := Color(0.09, 0.08, 0.13, 0.08)
const STRUT_COLOR := Color(0.18, 0.19, 0.24, 0.9)
const STRUT_EDGE := Color(0.4, 0.42, 0.5, 0.6)
const STRUT_WIDTH := 26.0
const MAX_STRUT_GAP := 320.0 # beyond this, platforms aren't meant to read as the same structure

func _ready() -> void:
	add_to_group("level_platforms") # lets the camera find this without a hard NodePath dependency
	# Draw order matters: backdrops, then struts, then platforms on top —
	# each layer is meant to be seen "through" the gaps in the one after it.
	for s in SECTIONS:
		_build_backdrop(s["x_start"], s["x_end"])
	_build_struts()
	for p in PLATFORMS:
		_build_platform(p["x"], p["y"], p["w"], p.get("route", "main"))
	for r in RAMPS:
		_build_ramp(r["x0"], r["y0"], r["x1"], r["y1"], r.get("route", "main"))

func level_end_x() -> float:
	var last: Dictionary = PLATFORMS[PLATFORMS.size() - 1]
	return last["x"] + last["w"]

## Top/bottom y of every platform whose x-range overlaps [from_x, from_x +
## ahead] — used by the camera to reveal a fork before you reach it instead
## of only ever showing whatever's at the car's own height.
func get_vertical_extent_ahead(from_x: float, ahead: float) -> Vector2:
	var min_y := INF
	var max_y := -INF
	for p in PLATFORMS:
		var p_start: float = p["x"]
		var p_end: float = p["x"] + p["w"]
		if p_end >= from_x and p_start <= from_x + ahead:
			min_y = min(min_y, p["y"])
			max_y = max(max_y, p["y"])
	for r in RAMPS:
		var r_start: float = min(r["x0"], r["x1"])
		var r_end: float = max(r["x0"], r["x1"])
		if r_end >= from_x and r_start <= from_x + ahead:
			min_y = min(min_y, min(r["y0"], r["y1"]))
			max_y = max(max_y, max(r["y0"], r["y1"]))
	if is_inf(min_y):
		return Vector2.ZERO # nothing found (shouldn't happen mid-level) -> caller treats as "no data"
	return Vector2(min_y, max_y)

## One solid backdrop panel spanning a whole section — purely visual (no
## collision), sitting behind everything else so the space between tiers
## reads as "inside a structure" instead of open void.
func _build_backdrop(x_start: float, x_end: float) -> void:
	var top := 100.0
	var bottom := 900.0
	var panel := Polygon2D.new()
	panel.polygon = PackedVector2Array([
		Vector2(x_start, top), Vector2(x_end, top),
		Vector2(x_end, bottom), Vector2(x_start, bottom),
	])
	panel.color = BACKDROP_COLOR
	add_child(panel)

## For every platform, finds the nearest platform below it that overlaps
## in x and connects them with a strut filling the gap — this is what
## turns "three floating rectangles" into "a three-tier scaffolded
## structure you can see all the way through."
func _build_struts() -> void:
	for a in PLATFORMS:
		var a_start: float = a["x"]
		var a_end: float = a["x"] + a["w"]
		var best_b: Dictionary = {}
		var best_gap := INF
		for b in PLATFORMS:
			if b == a:
				continue
			var b_start: float = b["x"]
			var b_end: float = b["x"] + b["w"]
			var overlap_start: float = max(a_start, b_start)
			var overlap_end: float = min(a_end, b_end)
			if overlap_end - overlap_start < 80.0:
				continue # negligible overlap, not meant to read as connected
			var gap: float = b["y"] - (a["y"] + THICKNESS)
			if gap < 30.0 or gap > MAX_STRUT_GAP:
				continue
			if gap < best_gap:
				best_gap = gap
				best_b = b
		if best_b.is_empty():
			continue
		var overlap_start: float = max(a_start, best_b["x"])
		var overlap_end: float = min(a_end, best_b["x"] + best_b["w"])
		var center_x: float = (overlap_start + overlap_end) * 0.5
		_build_strut(center_x, a["y"] + THICKNESS, best_b["y"])

func _build_strut(center_x: float, top_y: float, bottom_y: float) -> void:
	var half := STRUT_WIDTH * 0.5
	var fill := Polygon2D.new()
	fill.polygon = PackedVector2Array([
		Vector2(center_x - half, top_y), Vector2(center_x + half, top_y),
		Vector2(center_x + half, bottom_y), Vector2(center_x - half, bottom_y),
	])
	fill.color = STRUT_COLOR
	add_child(fill)

	# Thin edge lines so it reads as a girder, not just a dark block.
	for side in [-half, half]:
		var edge := Polygon2D.new()
		edge.polygon = PackedVector2Array([
			Vector2(center_x + side - 2, top_y), Vector2(center_x + side + 2, top_y),
			Vector2(center_x + side + 2, bottom_y), Vector2(center_x + side - 2, bottom_y),
		])
		edge.color = STRUT_EDGE
		add_child(edge)

func _build_platform(x: float, y: float, w: float, route: String) -> void:
	var colors: Array = ROUTE_COLORS.get(route, ROUTE_COLORS["main"])

	var body := StaticBody2D.new()
	body.collision_layer = 16 # terrain layer
	body.collision_mask = 0
	body.position = Vector2(x, y)

	var shape := RectangleShape2D.new()
	shape.size = Vector2(w, THICKNESS)
	var collider := CollisionShape2D.new()
	collider.shape = shape
	collider.position = Vector2(w * 0.5, THICKNESS * 0.5)
	# One-way, which is the genre standard and the real fix for "my head hits
	# the tile above". You land on a platform from above and pass straight up
	# through it from below, so a low ceiling can never trap or block you --
	# and the routes are free to converge without the lower one having to
	# tunnel under the upper one.
	collider.one_way_collision = true
	body.add_child(collider)

	var fill := Polygon2D.new()
	fill.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(w, 0), Vector2(w, THICKNESS), Vector2(0, THICKNESS),
	])
	fill.color = colors[0]
	body.add_child(fill)

	var lip := Polygon2D.new()
	lip.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(w, 0), Vector2(w, 6), Vector2(0, 6),
	])
	lip.color = colors[1]
	body.add_child(lip)

	add_child(body)

## A sloped solid connector between two heights — same layers/visual
## treatment as a platform, but its collision shape is a slanted quad instead
## of an axis-aligned rectangle, so the car just drives up/down it.
func _build_ramp(x0: float, y0: float, x1: float, y1: float, route: String) -> void:
	var colors: Array = ROUTE_COLORS.get(route, ROUTE_COLORS["main"])
	var top_pts := PackedVector2Array([
		Vector2(x0, y0), Vector2(x1, y1),
		Vector2(x1, y1 + THICKNESS), Vector2(x0, y0 + THICKNESS),
	])

	var body := StaticBody2D.new()
	body.collision_layer = 16
	body.collision_mask = 0

	var shape := ConvexPolygonShape2D.new()
	shape.points = top_pts
	var collider := CollisionShape2D.new()
	collider.shape = shape
	# One-way, same as the platforms. It matters most here: at every route
	# merge a descending ramp crosses over an ascending one, so without it the
	# player climbing out of the mid tier walks straight into the underside of
	# the high tier's descent and stops dead. A full run got stuck at x=18438
	# for 145 seconds on exactly that.
	collider.one_way_collision = true
	body.add_child(collider)

	var fill := Polygon2D.new()
	fill.polygon = top_pts
	fill.color = colors[0]
	body.add_child(fill)

	var lip := Polygon2D.new()
	lip.polygon = PackedVector2Array([
		Vector2(x0, y0), Vector2(x1, y1),
		Vector2(x1, y1 + 6), Vector2(x0, y0 + 6),
	])
	lip.color = colors[1]
	body.add_child(lip)

	add_child(body)
