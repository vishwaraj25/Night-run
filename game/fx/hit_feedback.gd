extends RefCounted
## Shared combat-readability helpers. Before this, nothing visibly happened
## when you shot an enemy -- health silently ticked down until it died, so
## you couldn't tell whether your bullets were connecting at all.
##
## Two separate colour channels on purpose, so they compose instead of
## fighting each other: damage uses `modulate`, attack telegraphs use
## `self_modulate`. A sprite mid-telegraph that also takes a hit shows both,
## because the renderer multiplies the two together.

const FLASH_TIME := 0.09

## White pop on taking a hit.
static func flash_hit(sprite: CanvasItem) -> void:
	if not is_instance_valid(sprite):
		return
	sprite.modulate = Color(5.0, 5.0, 5.0)
	var tw := sprite.create_tween()
	tw.tween_property(sprite, "modulate", Color.WHITE, FLASH_TIME)

## Red wind-up tint, strength 0..1, for "this thing is about to hit you".
static func set_telegraph(sprite: CanvasItem, strength: float) -> void:
	if not is_instance_valid(sprite):
		return
	sprite.self_modulate = Color.WHITE.lerp(Color(1.8, 0.35, 0.35), clampf(strength, 0.0, 1.0))
