extends RefCounted
## Shared terrain sensing for ground enemies, so they stop being things that
## walk in a straight line until the floor runs out.
##
## Every query here is a raycast against the terrain layer only (16, what
## level_builder.gd puts platforms and ramps on) — never against the player or
## other enemies, so an enemy standing in front of another doesn't read as a
## wall. All offsets are relative to the body's origin, which for these
## characters sits at the feet.

const TERRAIN_MASK := 16

## Is there floor under a point `offset_x` ahead of the feet? Starts slightly
## above the feet so a body already resting on the ground doesn't start the ray
## inside the platform it's standing on.
static func has_ground_at(body: CharacterBody2D, offset_x: float, depth: float = 220.0) -> bool:
	var from: Vector2 = body.global_position + Vector2(offset_x, -12.0)
	return not _ray(body, from, from + Vector2(0.0, depth)).is_empty()

## Solid terrain directly ahead at torso height — a wall or the side of a step,
## as opposed to open air.
static func wall_ahead(body: CharacterBody2D, dir: float, reach: float = 55.0, height: float = 60.0) -> bool:
	var from: Vector2 = body.global_position + Vector2(0.0, -height)
	return not _ray(body, from, from + Vector2(dir * reach, 0.0)).is_empty()

## How high this body's jump peaks, from the same physics the player uses:
## rise = v^2 / (2g). Used to decide whether a ledge is worth jumping at
## instead of hardcoding a number that silently goes wrong when speed changes.
static func jump_rise(jump_velocity: float, gravity: float) -> float:
	return (jump_velocity * jump_velocity) / (2.0 * gravity)

## How far it travels horizontally over a full jump arc: speed * 2v/g.
static func jump_reach(jump_velocity: float, gravity: float, speed: float) -> float:
	return speed * (2.0 * absf(jump_velocity) / gravity)

## Can a gap starting just ahead be cleared? Samples landing spots across the
## jump's reach and answers true if any of them has floor. Sampling beats a
## single probe at max range: most gaps in this level are narrower than a full
## jump, and a single far probe misses the near edge of the far platform.
## `drop_tolerance` deliberately stays small: has_ground_at's default 220px
## probe would happily accept a platform far below as a landing spot, so the
## enemy launched itself into pits aiming at floors it could never reach.
## `safety` keeps the target inside the arc rather than at its very tip, where
## the jump is already descending and lands on the lip at best.
static func gap_is_crossable(body: CharacterBody2D, dir: float, reach: float,
		drop_tolerance: float = 70.0, safety: float = 0.8) -> bool:
	var usable: float = reach * safety
	var step: float = maxf(usable / 6.0, 20.0)
	var d: float = step
	while d <= usable:
		if has_ground_at(body, dir * d, drop_tolerance):
			return true
		d += step
	return false

static func _ray(body: CharacterBody2D, from: Vector2, to: Vector2) -> Dictionary:
	var space := body.get_world_2d().direct_space_state
	var q := PhysicsRayQueryParameters2D.create(from, to)
	q.collision_mask = TERRAIN_MASK
	q.exclude = [body.get_rid()]
	return space.intersect_ray(q)

## World-space y of the first terrain surface below the body, or INF if there
## is nothing under it (a gap, or off the end of the level). Used by the flyer
## to hold an altitude over ground that changes height.
static func ground_height_below(body: CharacterBody2D, depth: float = 900.0) -> float:
	var from: Vector2 = body.global_position
	var hit := _ray(body, from, from + Vector2(0.0, depth))
	return hit["position"].y if hit.has("position") else INF

## Where an enemy's body actually is, taken from its collision shape rather
## than its origin (which sits at the feet for ground enemies and at the
## centre for flyers). Guessing a fixed torso offset is what had beam weapons
## passing over the shorter enemies.
static func body_centre(enemy: Node2D) -> Vector2:
	var shape := enemy.get_node_or_null("CollisionShape2D")
	if shape:
		return shape.global_position
	return enemy.global_position
