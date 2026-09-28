# Core Breach

A six degrees of freedom mine shooter built with [DragonRuby Game Toolkit](https://dragonruby.org), written as a tribute to the tunnel shooters of the mid-90s. The level, robots, textures and sounds are all original.

Two levels:

1. **The Mine:** find the blue and red keys, destroy the reactor, and escape before the self-destruct countdown runs out.
2. **The Deep Core:** descend a huge vertical shaft, collect three keys (blue, yellow, red), light your way through a blacked-out wing with flares, get past armoured wall turrets (lasers barely scratch them, use missiles) and splitters that break into two fast mini-hunters, destroy the core and climb out through the escape vent.

Score, lives and missiles carry over between levels. On the title screen, press a level's number to start there.

## Running

```sh
smaug run
```

The project uses DragonRuby Pro 7.13 through [Smaug](https://github.com/ereborstudios/smaug) (see `Smaug.toml`).

## Controls

| Input | Action |
| --- | --- |
| Mouse / arrow keys | Pitch and yaw |
| W / S | Thrust forward / reverse |
| A / D | Slide left / right |
| R / F | Slide up / down |
| Q / E | Roll |
| Left click / Space | Lasers |
| Right click / Ctrl | Concussion missile |
| G | Flare: sticks to walls and lights dark rooms for 20 s (2 energy) |
| Tab | Automap (mouse / arrows / A D rotate, W S / wheel zoom) |
| I | Invert mouse |
| Esc | Pause |
| 1 / 2 (title screen) | Start directly at a level |
| F1 | Show fps and triangle count |

Gamepad: sticks to fly, triggers to fire, Y for a flare, bumpers to roll, A/B to slide up/down, Select for the automap.

## Project layout

| File | Contents |
| --- | --- |
| `lib/d3d/` | Vendored copy of the [d3d](https://github.com/webmatze/d3d) engine (renderer, cell grid, 6DOF pose, meshes, automap). Don't edit here |
| `app/level.rb` | The mine: wraps a `D3D::CellGrid` and adds doors, exit, spawns and materials |
| `app/levels.rb`, `app/levels/*.rb` | Level definitions in play order: layout, pickups, robot spawns, wall lamps, countdown and texts |
| `app/meshes.rb` | Robot, reactor and pickup models (built with `D3D::FlatMesh`) |
| `app/game.rb` | Flight, weapons, robot AI, reactor, HUD, menus |
| `app/entities.rb` | Game object data holders |
| `tools/sync_d3d.sh` | Copies the d3d engine into `lib/d3d` (default source `../d3d`) and records its commit in `lib/d3d/SOURCE` |
| `tools/generate_assets.py` | Regenerates all textures (`sprites/game/`) and sounds (`sounds/`) |

To update the engine, change it in the d3d repository, then run `tools/sync_d3d.sh`.

---

# How the 3D engine works

DragonRuby has no 3D pipeline, no depth buffer and no shaders. What it does have is the ability to draw a **2D triangle with any part of a texture mapped onto it** (`x/y`, `x2/y2`, `x3/y3` plus `source_x…source_y3`). The engine does all 3D math in Ruby on the CPU and ends each frame with a sorted list of those triangles. It's the same approach as mid-90s software renderers.

The engine started in this game and now lives in the [d3d](https://github.com/webmatze/d3d) engine as its cell-grid renderer, vendored into `lib/d3d/`. The file references below point there.

## 1. The world is a grid of cubes (`D3D::CellGrid`, `lib/d3d/cell_grid.rb`)

- The mine (`app/level.rb`) is a 48×16×48 grid of 10-unit cells, each either open or solid. Rooms and tunnels are "carved" out of solid rock with box ranges in `app/levels/mine.rb`, and pillars and boulders are filled back in.
- `roughen` randomly raises floor cells and drops ceiling cells to make the caverns look less boxy. It uses a fixed-seed random number generator, so the level is identical every run, and it never touches cells next to doors or openings in the floor.
- **Wall generation:** every face where an open cell touches a solid one becomes a wall quad. Each quad stores its corner `c0`, two edge vectors (`eu`, `ev`), an inward-facing normal, a texture and a precomputed tint. The tint is the room's light colour times a per-direction shade: floors brightest, ceilings darkest, which gives cheap depth cues.
- Faces are rebuilt only when the geometry changes, i.e. when a door opens.
- The same grid gives cheap physics:
  - **Collision:** the ship is a sphere pushed out of any solid cells it overlaps, using the closest point on each cell's box.
  - **Line of sight:** sample points along a line and check whether each lands in an open cell.
  - **Doors:** solid cells with a special texture that turn into open cells.

## 2. Camera and transform (`D3D::Pose`, `lib/d3d/pose.rb`)

- The camera is a position plus three orthonormal vectors: right, up and forward. Rotation isn't stored as angles, which avoids gimbal lock and allows true 6-degrees-of-freedom flight.
- **Yaw, pitch and roll** each rotate one pair of those vectors around the third (`V.rotate_pair`). The vectors are re-orthonormalized every frame with cross products so rounding errors don't build up.
- **World to camera space** is three dot products: `cx = d·R`, `cy = d·U`, `cz = d·F`, where `d = point − camera`.
- **Perspective projection:** `sx = 640 + cx·f/cz`, `sy = 360 + cy·f/cz` with a focal length of 620, which gives roughly a 92° horizontal field of view.
- **Linearity trick:** a wall is transformed once as its corner plus two edge vectors. Any point on the wall in camera space is then `o + a·u + b·v`, so subdividing a wall costs additions, not new matrix math.

## 3. Deciding what to draw: flood-fill visibility (`CellGrid#visible_cells`)

`visible_cells` does a breadth-first flood fill through open cells, starting from the camera's cell. It crosses into a neighbour only if:

- the neighbour is within fog distance, and
- the shared face between the two cells (the "portal") is inside the view frustum.

The frustum test checks each of the portal's 4 corners against the near, left, right, top and bottom planes, which all pass through the camera. If all four corners are outside the same plane, the portal is invisible. Corner positions are cached per frame, since neighbouring cells share them.

This is a light version of portal rendering. It skips everything behind you and whole areas reachable only through off-screen tunnels. A distance limit is used instead of a step-count limit, because a step-count limit left holes in large rooms.

## 4. Drawing walls (`SceneRenderer#draw_face`, `lib/d3d/scene_renderer.rb`)

For each face of each visible cell, in order:

1. **Backface culling:** skip the face if the camera is behind it (dot product with the normal ≤ 0).
2. **Whole-face frustum reject.**
3. **Distance-based subdivision:** close walls are split into 4×4 sub-quads, then 3×3 and 2×2 further out, and 1 far away. DragonRuby's triangles use *affine* texture mapping (no perspective correction), so big, close triangles warp visibly. Smaller pieces hide that, and also reduce sorting errors.
4. **Near-plane clipping:** Sutherland–Hodgman clipping against `z = 0.4`, interpolating texture coordinates too. This keeps walls you're flying right next to from exploding to infinity.
5. **Projection and fan triangulation:** each clipped polygon becomes a fan of triangle sprites, with texture coordinates in texels of the 128×128 texture.
6. **Seam padding (`pad!`):** projected vertices are pushed about 0.7 px out from the polygon's centre so neighbouring triangles overlap. This hides hairline cracks from rasterization and from edges where neighbouring walls are split into different numbers of pieces.

## 5. Lighting (`SceneRenderer#light_at`)

Colour is computed once per sub-quad (flat shading) and applied through the sprite's `r/g/b` tint, which multiplies the texture:

- the room's tint × direction shade
- plus a **headlight** term that falls off within 60 units
- × **fog** that fades to black by distance 140. The fog also works as a draw-distance cutoff.
- plus **dynamic point lights** (laser bolts, muzzle flashes, explosions), each with a linear falloff. Only the 8 nearest are used.
- plus a global "boost", which drives the red alarm pulse during the countdown.

## 6. Objects: meshes and billboards

- **Meshes** (`D3D::FlatMesh` in `lib/d3d/flat_mesh.rb`; the game's models are in `app/meshes.rb`) are small vertex/triangle lists built from helpers such as `box` and `bipyramid`.
  - Winding is fixed automatically so normals point outward, away from each part's centre.
  - Fins and blades are marked double-sided; eyes and the reactor core are "emissive" (unlit).
  - Triangles are drawn with a tinted 8×8 white texture, with a camera-facing shade similar to Lambert lighting.
  - A hit flash blends the colour toward white.
- **Billboards** (projectiles, particles, explosion flashes, pickup halos) are a generated radial-gradient `glow.png`. It's scaled by `1/z` and drawn with **additive blending** (`blendmode_enum: 2`), which gives the glowing plasma look for free.

## 7. Hidden-surface removal: painter's algorithm

There's no depth buffer, so every primitive (wall triangles, mesh triangles, billboards) goes into one list keyed by squared distance. The list is sorted back to front and pushed to `args.outputs.sprites` in one go. Nearer surfaces are simply drawn over farther ones.

Painter's sorting can fail when a robot sits behind a wall corner, so robots and pickups are only drawn when a **line-of-sight raycast** from the camera reaches them. That stops them showing through rock.

**Screen shake** jitters the camera position and roll before rendering, rather than shifting the image.

## 8. The automap (`D3D::GridMap`, `lib/d3d/grid_map.rb`)

- Every frame, the cells the renderer's flood fill found visible within 100 units are marked as explored, so the map only shows what you've actually seen.
- Each explored cell adds the outline edges of its walls as 3D line segments. An edge is skipped when the wall continues flat into the neighbouring cell, so big walls show up as clean outlines instead of a grid of squares.
- Edges are de-duplicated by a key built from their two grid corners. Door and exit edges override plain wall edges so they always show in their colour.
- The map is drawn with an orbit camera around the ship using the same projection as the main renderer, with near-plane clipping per line and brightness fading with depth. The ship, seen keys and the reactor are drawn as small wireframe markers.
- The game pauses while the map is open. When a door has opened since the last look, the edges are rebuilt from the explored cells.

## 9. Assets without art files

`tools/generate_assets.py` uses only the Python standard library to write:

- **PNGs** by hand (zlib + CRC chunks): rock textures from repeating layered value noise, metal and tech panels with seams and rivets, striped doors, a grate, and the glow sprite.
- **WAVs:** a falling square-wave laser, filtered-noise explosions and whooshes, and a rising-and-falling alarm.

Regenerate them with:

```sh
python3 tools/generate_assets.py
```

## 10. DragonRuby details that mattered

- Integer `/` returns a float in DragonRuby. Use `idiv` for integer division.
- `keyboard.up`/`down`/`left`/`right` also match W/S/A/D. Use the `*_arrow` variants when the arrow keys need their own meaning.
- `solids` are deprecated; HUD rectangles are sprites with `path: :solid`.
- `set_mouse_grab 2` gives relative mouse mode for mouselook.
- Hot paths use local floats and inline math instead of vector-helper calls, to limit Ruby allocations.

The renderer draws roughly 400–1,200 triangles per frame and held 57–60 fps in every area of the level during testing.
