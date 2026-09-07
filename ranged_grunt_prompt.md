# Ranged grunt — sprite sheet spec

A gun-carrying humanoid ground enemy, to become the main ground threat in place
of the sentry bot (which is trap art doing a job it wasn't drawn for).

Every requirement below exists because of a specific thing that went wrong on one
of the sheets already in the game. The "why" column is the important part — if a
generator can't hit one of these, tell me which one and I'll work around it in
code rather than you regenerating five times.

---

## The five things that must be right

### 1. Exact grid: 8 columns × 5 rows, 1472 × 1045 px
184 × 209 per cell, evenly spaced, no gutters, no borders.

**Why:** the code addresses frames as `row * 8 + col`. It matches
`enemy_grunt_spritesheet.png` exactly, so the new sheet reads with the same
maths and no new code path. An uneven grid shears every frame.

### 2. The character faces RIGHT in every side-view frame
**Why:** this is the bug you spotted in the screenshot. Both existing enemy
sheets face right and the code mirrors for left. A left-facing sheet looks
correct in the generator and renders backwards in the game — the enemy walks at
you facing away.

### 3. Flat magenta `#FF00FF` background — do not ask for transparency
No gradient, no drop shadow, no glow bleeding into it.

**Why:** every generator so far has returned a "transparent" PNG whose alpha
channel is fully opaque. Magenta gets chroma-keyed cleanly by the pipeline
already built for the boss and drone sheets.

### 4. Feet on a consistent baseline in every frame of every row
Same ground line, same horizontal centring, in idle, run, firing and death.

**Why:** the sprite is bottom-aligned to its collision box once, from one
measurement. Frames drawn at different heights make the character bob into and
out of the floor as it animates. This is what had the boss floating 110px above
the ground.

### 5. The gun is visible and held in BOTH hands in every pose — including idle and run
And the muzzle flash must sit **at the barrel tip**, fully inside the cell, not
clipped by the cell edge and not bleeding into the neighbouring frame.

**Why, and this is the one that matters most:** I locate the barrel by diffing a
no-flash frame against a flash frame and taking the brightest gain. That measured
point becomes `muzzle_offset` — where bullets actually spawn. Get this right and
shots leave the gun; get it wrong and they come out of the character's chest,
which is exactly what every enemy in the game was doing until this week.

For that diff to work, **the body must be in nearly the same pose in the wind-up
frames and the flash frames** — the only large change between them should be the
flash itself. A recoil that throws the whole body around between those frames
makes the barrel unmeasurable.

---

## Row layout

| Row | Contents | What the code does with it |
|-----|----------|---------------------------|
| 0 | **Idle** — 8 near-identical standing frames, weapon at low ready, slight breathing sway | Played when it's holding station at a ledge or out of range |
| 1 | **Run** — full 8-frame cycle, weapon carried across the body | Played while it closes or backs off |
| 2 | **Fire, horizontal** — cols 0–2 weapon raised, **no flash** · cols 3–7 **flash at the barrel tip** | Cols 0–2 are the wind-up the red telegraph ramps across; cols 3–7 are where shots spawn |
| 3 | **Fire, angled up ~30°** — same split: cols 0–2 no flash, cols 3–7 flash | Used when the player is on a ledge above it |
| 4 | **Death** — cols 0–2 stagger back / hit reaction, col 3 collapsing, cols 4–7 progressively settled on the ground | Plays once, then freezes on col 7; the explosion effect fires on the first frame |

Two notes on row 4: **col 7 must be a stable resting pose** (the corpse is left on
screen for a beat before it despawns), and the death frames should read clearly
as *this* character dying — not a generic puff of smoke, since there's already a
code-drawn explosion layered over it.

---

## The prompt

> Pixel art sprite sheet, 8 columns by 5 rows, evenly spaced grid, flat magenta
> #FF00FF background. A cyberpunk enemy soldier in dark battle-worn armour with
> red glowing accents and a cracked white helmet visor, carrying a compact rifle
> in both hands, side view facing right, same size and ground line in every
> frame. Row 1: idle standing loop, rifle held at low ready. Row 2: eight frame
> run cycle, rifle carried across the body. Row 3: firing the rifle straight
> ahead — first three frames weapon raised and steady with no muzzle flash, last
> five frames identical stance with a bright orange muzzle flash at the barrel
> tip. Row 4: firing the rifle upward at a thirty degree angle, same pattern —
> first three frames no flash, last five with a muzzle flash at the barrel tip.
> Row 5: death sequence — staggering back, collapsing, then settled on the
> ground. Gritty neon-noir palette of charcoal, steel grey, deep red and cyan
> highlights. Crisp pixel art, no anti-aliasing on the outline, no text, no
> borders, no drop shadows, no motion blur.

**Midjourney:** append `--ar 7:5 --style raw --no text, watermark, border, shadow, gradient background, motion blur`

---

## What happens when it lands

Drop it in Downloads and tell me. Before a line of script gets written I check,
the same way I did for the boss and drone:

1. Real pixel dimensions and whether the grid divides evenly
2. Whether the alpha is genuine or fake (it has been fake every time so far)
3. Which way it faces
4. Feet baseline consistency across rows
5. Where the muzzle flash actually lands, measured by frame diff

Then chroma-key it, measure the collision box off the run row, set the sprite
offset and scale from the content bounds, and wire it into the ranged behaviour
that already exists in `enemy_shooter.gd` — pathing, standoff, telegraph and
explosion all carry over unchanged.

If any of the five checks fails I'll tell you which one and what it costs, rather
than wiring it up and letting you find it in-game.
