# Plan: Level 2 "The Deep Core"

## Goal

Top level 1 by using what it didn't:
- **depth:** a huge vertical shaft;
- **darkness:** a blacked-out wing lit only by the headlight and flares;
- **a boss** instead of a stationary reactor.

A collapsing escape route and a third key round it off. Each step below ends in a playable game, so balance can be checked as it grows.

## Level concept

Grid 48×40×48 cells (level 1 is 48×16×48). Keys in order: blue → yellow → red.

| Area | Where | Content |
|---|---|---|
| Arrival dock | top of the level, metal | Player start, missiles pickup, short tunnel into the shaft |
| **The Great Shaft** | centre, ~12×34×12 cells, rock + crystal | Ledges sticking out of the walls, two cross-bridges, side galleries at different heights. Turrets on the walls, drones flying. **Pylon 1** on a ledge halfway down |
| West gallery | high, rock | Turrets + drones guard the **blue key** |
| Blackout wing | mid height, east, behind the **blue door** | Tech maze with light level ~0.05. Only the headlight and flares light it. Splitters. **Pylon 2** and the **yellow key** |
| Magma caverns | bottom, south, behind the **yellow door** | New cooled-magma texture, splitters and brutes. **Pylon 3** and the **red key** |
| Core chamber | bottom, north, behind the **red door** | The boss, the Warden |
| Escape vent | from the core chamber ceiling up to the top | Narrow vent next to the shaft, opens when the Warden dies, ends in the exit |

**The escape twist.** When the Warden dies, the countdown (60 s) starts. The magma route you came in through collapses cell by cell behind you, so you're forced up through the escape vent, which you've only seen on the map before.

## Step 0: Engine changes (d3d, separate PR)

Runtime changes to the grid currently rebuild every wall (`CellGrid#rebuild_faces` walks all cells). That's fine for one door on a 36k-cell grid, but a collapse fills many cells on a 92k-cell grid. The fix belongs in d3d:

- `CellGrid#rebuild_faces_near(n)`: recomputes the faces of cell `n` and its 6 neighbours only. `unseal` uses it.
- `CellGrid#solidify(i, j, k)`: turns an open cell solid at runtime and calls `rebuild_faces_near`. This is used by the collapse.
- `CellGrid#version`: a counter bumped on every runtime change. `GridMap#open` rebuilds its edges when the version changed; today it only notices a change in blocker count, which misses collapses.
- **Tests:**
  - local rebuild gives the same faces as a full rebuild;
  - `solidify` removes the cell's faces and adds walls to its neighbours;
  - `GridMap` picks up a version change.
- **Bench:** check that visibility and rendering still keep up on a tall grid, adding a tall-shaft scene to `bench/scenes.rb`.

Then sync the engine into the game with `tools/sync_d3d.sh`.

## Step 1: Multiple levels

- **Level definitions:** move `LevelData` to `app/levels/level1.rb` (`Levels::Mine`) and add `app/levels/level2.rb` (`Levels::DeepCore`). Each defines:
  - `build(l)`, which carves the grid;
  - `name` and `briefing`;
  - `grid_size`;
  - `countdown` (seconds);
  - `objective` (`:reactor` or `:boss`).

  `Level.new(defn)` builds the grid from these.
- **Game:**
  - `setup_level(number)` builds the world;
  - the ship's score, lives, missiles and keys-reset live in a `Campaign` object that survives between levels;
  - a new `:intermission` state shows kills, time and bonus, and Enter goes to the next level;
  - `:victory` only happens after the last level.
- **Title screen:** 1/2 keys start directly at a level (practice).
- **Keys become generic:** `:yellow` door/key, a `door_yellow` material, a yellow key mesh, a yellow HUD slot and a map colour. `collect` handles any `*_key` pickup.
- **Level 2 in this step:** a first playable version of the layout, with the level 1 robots and a reactor as a placeholder objective.

## Step 2: Flares and the blackout wing

- **Flares:** a new weapon on **G** (gamepad **Y**).
  - Costs 2 energy, 1 s cooldown.
  - Flies slowly and sticks to the wall it hits.
  - Stuck flares become `Flare` entities (20 s life, with a slight flicker). Each frame they add a warm point light (radius ~40) plus a glow sprite.
  - At most 6 active; the oldest burns out first.
- **Dark rooms:** the blackout wing's cells get a near-zero tint. Nothing else is needed, because the renderer's headlight already works on its own.
- **HUD and title:** add a flare hint to the controls list and the title screen.

## Step 3: New enemies

Both use the existing `Robot` class with new `STATS` entries. `Robot` gets a `scale` field, and meshes are drawn scaled.

- **Turret** (`:turret`):
  - Spawned with the normal of the wall it's mounted on. It never moves (skips velocity and collision) and only turns towards the player.
  - 60 HP. Takes 25% damage from lasers and full damage from missiles.
  - Fires 2-shot bursts every 1.6 s up to 80 units.
  - Mesh: a flat dome with a barrel.
- **Splitter** (`:splitter`):
  - 40 HP, slow.
  - On death it spawns 2 mini-hunters: the hunter behaviour at scale 0.6, 10 HP, faster.
  - Mesh: a double-diamond body that visibly "opens" when hit.

## Step 4: The Warden and the pylons

- **Pylons** (new entity):
  - Stationary, 120 HP, a tall crystal mesh with a pulsing glow.
  - When destroyed: an explosion and a message ("Shield pylon destroyed, 2 remaining").
  - The HUD shows `PYLONS 1/3` while the boss is alive.
- **Warden** (`:boss`, new entity):
  - Radius ~7, 600 HP, slow.
  - Alternates two attacks: a 5-shot plasma spread, and summoning 2 drones every 20 s (capped at 4 alive).
  - While any pylon stands, hits only spark blue off its shield (with a shield hit sound) and do no damage.
  - Its death starts the countdown, like the reactor in level 1 (`objective: :boss`).
  - Mesh: a large armoured octagon with a glowing core that's visible through its gaps.
- **Map:** the automap shows pylon markers once they're explored.

## Step 5: The collapsing escape

- **Collapse sequence:** level 2 defines `collapse: [[i, j, k, seconds_after_countdown_start], ...]` along the magma route.
- **Each collapse event:**
  - calls `grid.solidify` on the cell;
  - plays dust and rock-debris particles, screen shake and a rumble sound.
- **Safety:** a cell is never filled while the ship overlaps it. It's retried every 0.5 s, so the player can never be trapped inside rock. Robots inside a collapsing cell are destroyed.
- **Exit:** the escape vent's exit door opens when the Warden dies (the same mechanism as level 1's hatch).

## Assets (`tools/generate_assets.py`)

- **Textures:** `magma_crust` (dark crust with glowing cracks), `crystal` (teal facets), `door_yellow`.
- **Sounds:** `flare`, `shield_hit`, `rumble`, `pylon_down`.

## Verification (every step)

- **Scripted smoke test:** extend the temporary harness used before with the level 2 areas (dock, shaft top/middle/bottom, west gallery, blackout wing with and without a flare, magma caverns, core chamber, escape vent, automap). It takes screenshots and logs fps and triangle count per area.
- **Flow checks:**
  - level 1 → intermission → level 2, with score, lives and missiles carried over;
  - each door and key;
  - flare sticking and lighting;
  - turret armour;
  - splitter splitting;
  - pylon → boss shield → boss death → countdown;
  - the collapse, including never filling the ship's cell;
  - exit → victory;
  - death and respawn in level 2.
- **Performance target:** ≥ 50 fps in the shaft. If the open shaft draws too many triangles, lower that level's fog distance (per-level renderer setting) or narrow the shaft before touching the engine.
- **d3d:** new tests pass, and the bench shows no regressions.
- **By hand:** a manual play-through of both levels.

## Delivery

- **d3d:** Step 0 as its own PR.
- **Game:** Steps 1–5 on a `feat/level-2` branch, one commit per step, as one PR (or one per step if you prefer smaller reviews).
