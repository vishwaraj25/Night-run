extends Node2D
## Fades the bottom edge of the city backdrop out instead of letting it stop
## dead.
##
## The backdrop is a 720px sprite in a parallax layer, and the layer is scaled
## by the camera's zoom. At the widest fork zoom (0.6) it only reaches 427px
## down a 540px screen, so the art ended partway up the view. The clear colour
## behind it now matches the artwork's bottom edge closely enough that the flat
## area itself is invisible -- but the lit signs and windows that happen to
## reach the sprite's last row were still being sliced off in a hard straight
## line right across the screen.
##
## This is a child of the same ParallaxLayer as the sprite, so it inherits the
## same transform and the same zoom scaling, and therefore sits exactly on the
## sprite's bottom edge at every zoom level without anything having to
## recompute it. It is a later sibling, so it draws on top.

## In layer space. The sprite is 5245x720 centred at (2622, 350), so its bottom
## edge is y = 710 and it spans x = -0.5 to 5244.5.
const FADE_TOP := 560.0
const FADE_BOTTOM := 712.0
const DEPTH_BELOW := 1600.0
const SPRITE_LEFT := -0.5
const SPRITE_WIDTH := 5245.0

## Matches rendering/environment/defaults/default_clear_color, which was in turn
## sampled from the bottom edge of bg_mid.png.
const CLEAR := Color(0.164, 0.125, 0.184, 1.0)

func _draw() -> void:
	var clear_transparent := Color(CLEAR.r, CLEAR.g, CLEAR.b, 0.0)

	# One mirroring period wide, so ParallaxLayer's motion_mirroring repeats it
	# in step with the sprite rather than leaving gaps between tiles.
	draw_polygon(
		PackedVector2Array([
			Vector2(SPRITE_LEFT, FADE_TOP),
			Vector2(SPRITE_LEFT + SPRITE_WIDTH, FADE_TOP),
			Vector2(SPRITE_LEFT + SPRITE_WIDTH, FADE_BOTTOM),
			Vector2(SPRITE_LEFT, FADE_BOTTOM),
		]),
		PackedColorArray([clear_transparent, clear_transparent, CLEAR, CLEAR]))

	# Below the artwork entirely. The clear colour already covers this, but not
	# if someone retunes the zoom or the backdrop later.
	draw_rect(Rect2(SPRITE_LEFT, FADE_BOTTOM, SPRITE_WIDTH, DEPTH_BELOW), CLEAR)
