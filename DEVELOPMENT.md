# Night Run — how this gets developed

Written for whoever picks this up next, including you in three months. It is
less about the code (that is commented) and more about the working method,
because the method is what kept catching bugs that reading the code did not.

Commands below assume `godot` runs the Godot 4.7.2 editor from your terminal.
If it does not, use the full path to the binary you installed instead.

## The one rule that matters

**Verify against the running game, not against the code.**

Almost every serious bug in this project passed code review in my own head and
was caught only by making the engine do the thing and measuring the result.
A representative list, all of them real:

| Bug | Reading the code said | Running it said |
|---|---|---|
| No enemies in the level | Spawner looks fine | 4 static traps saturated `max_alive`; **0 mobile enemies all level** |
| Bullets not hitting | Cone test looks fine | Enemy 43px below the gun is 10° off — beam drew straight over its head |
| Flamethrower too short | `range_px = 340` in the script | `.tscn` overrode it to **90**; the script value never applied |
| Two thirds of fork 2 empty | Timeline has plenty of entries | Grouped by tier, so entries fired 3500px behind the player |
| Boss "moonwalking" | Facing code exists | Boss never flipped at all; art faces right, it walks left |
| Boss falls out of the world | Spawn point is on the floor | Placed *flush* with a one-way platform → dropped through |
| Boss floating at y=350 | Position clamp works | Player walks through it; solver ejected it upward instead |
| Android portrait | `orientation=1` reads as "landscape" | Built manifest declared **portrait** for a side-scroller |
| A `match` branch missing | The edit reported success | Boss sat inert in that state for 513 frames |
| Shield sound "popping" | Raise plays once per raise | One 8s hold raised it **7 times**: regen refilled a sliver, that sliver cleared `> 0` for one frame |
| Character runs on its own | Nothing moves it without input | With the key-up withheld it ran at full speed for **121 of 121** frames sampled |
| Firing after death | Controller returns early when dead | `WeaponManager` has its own `_process`: still firing **73 frames** later |
| Shooting backwards on a phone | Aim follows facing | `emulate_mouse_from_touch` is on by default, so a thumb on a pad *is* a mouse position |
| Menu untappable on a phone | Buttons are placed correctly | Placed for one aspect ratio; the art is `KEEP_ASPECT_COVERED`, so the words move and the hitboxes do not |
| Grey band when the view widens | Backdrop covers the screen | At zoom 0.6 the backdrop reached 427px down a 540px view: **21.1%** of the frame was the default clear grey |

The last one is worth internalising: **a string-replace edit that does not match
silently does nothing.** Every structural edit now asserts its pattern matched
before writing.

## How verification actually works here

There is no test framework in the Godot project. Instead, throwaway probe
scenes drive the real game headless and print measurements.

```gdscript
# game/world/_temp_<thing>.gd  — instances world/level.tscn, synthesises input,
# counts what happened, prints, quits. Deleted once the numbers are confirmed.
```

Run one:

```bash
godot --headless \
  --path game res://world/_temp_verify.tscn
```

Rules that came out of getting this wrong repeatedly:

- **Name them `_temp_*` and delete them when done.** They are scaffolding.
- **Make the probe survive the thing it is measuring.** Several runs produced
  garbage because the probe itself died: `level.gd` swaps to the main menu on
  death and tore the probe down mid-run; a probe that revived the player's
  health but not its `_dead` flag froze at x=21927 for 150 seconds.
- **Distrust a clean result more than a dirty one.** A "9.8s gap in the tower"
  turned out to be the probe free-falling with `y` in the tens of thousands, so
  every later encounter failed its tier check. The level was fine.
- **Identical numbers across runs mean nothing changed.** Adding encounters
  produced byte-identical output twice; that is what exposed the tier-ordering
  bug, not any amount of staring at the list.
- **A bot is not a player.** It holds "run right", so it faces away from a boss
  standing to its left and never lands a shot. Give it just enough behaviour to
  exercise what you are testing, and read failures with that in mind.

Rendering needs a real window — headless has no rendering context:

```bash
godot \
  --path game res://world/_temp_look.tscn      # probe calls save_png()
```

## Art pipeline

Every generated sheet has arrived with the same three problems, so there is a
tool for each, in `tools/`:

1. **Fake transparency.** Every sheet so far reported alpha extrema `(255,255)`
   — fully opaque despite being asked for transparency. Generate on **flat
   magenta `#FF00FF`** and run `tools/chroma_key.py`, which does a soft alpha
   ramp, colour decontamination, and spill suppression (the purple halo that
   survives the first two passes).
2. **Bleed between cells.** Muzzle flashes run past their own frame.
   `tools/clean_cells.py` drops components that sit entirely in a cell's left
   margin.
3. **Rows at different heights.** The turret sheet's rows had their feet 25px
   apart, which makes a sprite jump every time it fires. `tools/align_rows.py`
   puts every row on one ground line.

Then measure before writing any script: real pixel dimensions, whether the grid
divides evenly, which way it faces (**both existing enemy sheets face right**;
assuming left was a real bug), the content bbox for collision sizing, and the
muzzle position by diffing a no-flash frame against a flash frame.

`ranged_grunt_prompt.md` is the spec to hand a generator, with the reasoning
for each requirement.

## Sound

All 18 effects are **synthesised**, not sourced — `tools/make_sfx.py` writes
them with numpy. Generated rather than downloaded for three reasons: no
licensing to worry about on a public link, the whole set is 304 KB, and a sound
can be tuned to the thing it represents instead of settling for the nearest
match in a pack. The seed is fixed, so regenerating gives the identical set.

```bash
python3 tools/make_sfx.py          # rewrites game/assets/sfx/
```

`game/autoload/audio.gd` is the only thing that touches playback. Three
problems it exists to solve, all of which bit before it did:

- **Voice count.** A 0.13s fire rate, times several enemies, times impact
  sparks, is dozens of overlapping voices a second. A fixed pool of 16 with
  oldest-voice stealing means audio can never be what stalls the game. A real
  run peaked at 6.
- **Retrigger spacing.** The same sound twice in one millisecond is not louder,
  it is a phasing artefact — the double MG's two barrels came out as one
  clipped click. Every sound has a minimum gap, tuned to its own length.
- **Orphaned loops.** The laser and flamethrower loop while held. A weapon can
  be swapped out mid-beam when its pickup timer expires, and the boss can die
  mid-sweep; either would leave a loop playing for the rest of the session with
  nothing driving it. `_exit_tree` and the death path stop them, and the probes
  assert `Audio._loops` is empty afterwards.

**M mutes.** This ships as a link and someone will open it with their volume up.

Verified by running: 9 distinct one-shots fired across a 90s run, the laser
loop opened and closed cleanly, and the boss fight left no loop open. What that
does *not* tell you is whether they sound good — that needs ears.

## Level geometry

`game/world/level_builder.gd` is the authority — `PLATFORMS` and `RAMPS`, plain
data. The player's envelope, which everything is authored against:

```
move_speed 260, jump_velocity -520, gravity 1400
  single jump  97px rise, ~193px horizontal reach
  double jump  ~193px rise
  body         109 x 150, origin at the feet
  slab         THICKNESS = 26
```

Two constraints that are easy to violate:

- **Headroom.** A stacked pair needs `y_lower - y_upper - 26 >= 150` for the
  player to stand. The level was originally authored for the 60px-tall car;
  when it became a 150px humanoid, **25 platform pairs were unstandable**,
  including the whole fork-2 mid tier. Re-check after any vertical change:

  ```bash
  # the headroom audit used throughout this project
  python3 - <<'EOF'
  import re
  b = open("game/world/level_builder.gd").read().split("const PLATFORMS")[1].split("]")[0]
  p = [(int(m[0]), int(m[0])+int(m[2]), int(m[1])) for m in
       re.findall(r'\{"x":\s*(-?\d+),\s*"y":\s*(-?\d+),\s*"w":\s*(\d+)', b)]
  bad = [(a[2]-c[2]-26, a) for a in p for c in p if c is not a and c[2] < a[2]
         and min(a[1],c[1]) > max(a[0],c[0]) and (a[2]-c[2]-26) < 150]
  print("pairs where a 150px character does not fit:", len(bad))
  EOF
  ```

- **Reachable *and* walkable is a narrow band.** Over a y=500 floor, a ledge
  must be within the 193px double jump (`y >= 307`) and clear a 150px body
  underneath (`y <= 324`). The floating ledges all sit at 315.

Platforms and ramps are **one-way**. That is the fix for "my head hits the tile
above", and it is what lets converging routes cross. It also means **anything
spawned flush with a platform falls through it** — spawn from above, with
margin. That bug bit the boss and the enemy spawner separately.

## Pacing

Combat density is measured, not guessed:

```
dead stretches over 3s     3  ->  none
run with nothing near     25% ->  12%
```

The probe samples enemies within 1100px each frame and reports gaps over 3s
with the x they start at. When a gap does not move after you add encounters
there, the spawner is the problem, not the content.

## Backend

```bash
cd backend && npm test     # 26 tests
```

Two suites, and the split is deliberate:

- `validation.test.js` — the validator in isolation.
- `integration.test.js` — the real server over real HTTP with the database
  stubbed, asserting on **the exact parameters that would reach Postgres**.

The second is the one that backs `PRIVACY.md`. "The validator returns null for
an email field" and "an email field cannot reach the database" are different
claims, and only the second is worth writing down.

Never verified: no Postgres or Docker on this machine, so the schema has never
been applied and the pool has never opened a real connection.

## Building

```bash
G=godot

$G --headless --path game --import                                   # after any asset change
$G --headless --path game --export-release "Web"     ../build/web/index.html
cp deploy/_headers build/web/_headers                                 # export does not carry this over
$G --headless --path game --export-debug   "Android" ../build/night-run.apk
cd build/web && zip -rq ../night-run-web.zip .                       # itch upload
```

**Always check the built artefact, not the config.** `aapt2 dump badging` on
the APK is what exposed the portrait orientation; the project setting reads
plausibly either way.

## Git

Small commits, each with a message explaining *why* and what the measurement
said. Tags mark known-good points — `git tag` lists them; `git checkout
<tag>` goes back. There is **no remote configured**; everything is local.

Nothing under `build/` is tracked: it is all reproducible from source.

## Input, and why there is an InputGuard

Three separate bugs came from the same root: **a press and its release are two
events, and nothing guarantees you get the second one.**

- A browser tab that loses focus mid-run never delivers the key-up. Godot keeps
  the action pressed, so the character runs off on its own. This is the web
  build's normal condition, not an edge case.
- A `TouchScreenButton` that is freed mid-press (scene change, death, level
  unloading under a thumb) never releases its action either.
- `Input.action_press` sets action *state* without sending an *event*, so
  anything listening in `_unhandled_input` cannot be driven by an on-screen pad
  at all. The pause overlay was written that way and could only ever have been
  triggered by a key, never by a touch.

`autoload/input_guard.gd` owns the first two: it releases every holdable action
on focus loss, and the pads call it when they leave the tree. The third is why
the pause overlay polls the action instead of listening for it -- polling is the
one path a key and a pad both take.

## Two coordinate spaces that are not the same space

Both mobile layout bugs were a value being measured against the wrong rectangle.

- `DisplayServer.get_display_safe_area()` and `DisplayServer.screen_get_size()`
  are not in the same space on the web build: the browser reports the whole
  device screen while the safe area describes the canvas. Dividing one by the
  other produced a bottom inset of a large fraction of the view and threw the
  touch pads into the middle of the screen. `_safe_insets` now measures against
  the *window*, refuses a safe area that does not fit inside it, and caps any
  inset at 12%.
- The menu's words are painted into the background art, which is drawn with
  `KEEP_ASPECT_COVERED`. Fixed pixel offsets only line up at the one aspect
  ratio they were authored against. The hitboxes are now stored as fractions of
  the image and mapped through the same cover transform at runtime, so they
  track the text at every size. The fractions were measured off the artwork by
  finding its near-white glyph pixels (the city neon behind them is saturated,
  the lettering is not) rather than converted from the old offsets -- those were
  themselves short, stopping 57px before the end of the Y in PLAY.

## Known open items

- **Untested on real phone hardware.** Touch pad placement was verified by
  rendering the real level at phone aspect ratios (20:9, iPhone landscape, 4:3)
  and looking at the result, and the menu hitboxes the same way. What that does
  not tell you is how the pads feel under an actual thumb.
- **The player does not collide with enemies** (mask is terrain-only). Contact
  damage works because enemies detect the player. The boss now ignores the
  player's body entirely and measures overlap itself, because being walked
  through was ejecting it out of the arena. The other enemies still use the
  physics path.
- **`ranged_grunt_prompt.md`** is written but the sheet was never generated;
  the ground enemy is the repurposed turret art.
- **Jetpack has no crate art** and falls back to the drawn capsule.
- **The backend has never talked to a real database.**
