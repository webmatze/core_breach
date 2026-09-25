# The mine: a D3D::CellGrid plus the game rules on top of it (key doors, the
# exit hatch, spawn points, player start and reactor position).
CS = 10.0 # cell size in world units

class Level
  MATERIALS = {
    rock:      { path: 'sprites/game/rock.png', size: 128 },
    rock_dark: { path: 'sprites/game/rock_dark.png', size: 128 },
    lava:      { path: 'sprites/game/lava_rock.png', size: 128 },
    metal:     { path: 'sprites/game/metal.png', size: 128 },
    tech:      { path: 'sprites/game/tech.png', size: 128 },
    grate:     { path: 'sprites/game/grate.png', size: 128 },
    door_blue: { path: 'sprites/game/door_blue.png', size: 128 },
    door_red:  { path: 'sprites/game/door_red.png', size: 128 },
    door_exit: { path: 'sprites/game/grate.png', size: 128 }
  }
  DOOR_MATERIALS = { blue: :door_blue, red: :door_red, exit: :door_exit }

  attr_reader :grid, :spawns, :player_start, :exit_cells, :reactor_pos

  def initialize
    @grid = D3D::CellGrid.new(48, 16, 48, cell_size: CS)
    @spawns = []
    @exit_cells = {}
    LevelData.build(self)
    @grid.rebuild_faces
  end

  # ----------------------------------------------------------- construction (used by LevelData)

  def carve(i0, i1, j0, j1, k0, k1, material, tint)
    @grid.carve(i0, i1, j0, j1, k0, k1, material, tint)
  end

  def fill(i0, i1, j0, j1, k0, k1)
    @grid.fill(i0, i1, j0, j1, k0, k1)
  end

  def roughen(i0, i1, j0, j1, k0, k1, count, rng)
    @grid.roughen(i0, i1, j0, j1, k0, k1, count, rng)
  end

  def add_door(i, j, k, kind)
    @grid.seal(i, j, k, kind, material: DOOR_MATERIALS[kind])
  end

  # Exit cells get grate walls and end the level when entered.
  def mark_exit(i, j, k)
    n = @grid.idx(i, j, k)
    @grid.carve(i, i, j, j, k, k, :grate, @grid.tint_of(n))
    @exit_cells[n] = true
  end

  def set_reactor(pos)
    @reactor_pos = pos
  end

  def set_player_start(pos)
    @player_start = pos
  end

  def spawn(kind, i, j, k)
    @spawns << [kind, @grid.cell_center(i, j, k)]
  end

  # ----------------------------------------------------------- queries

  def solid_at?(p)
    @grid.solid_at?(p)
  end

  def los?(a, b, step = 2.0)
    @grid.los?(a, b, step)
  end

  def collide_sphere(pos, r)
    @grid.collide_sphere(pos, r)
  end

  def tint_at(p)
    @grid.tint_at(p)
  end

  def exit_at?(p)
    i, j, k = @grid.cell_of(p)
    @exit_cells[@grid.idx(i, j, k)]
  end

  # ----------------------------------------------------------- doors

  # cell index => :blue / :red / :exit for every closed door
  def doors
    @grid.blockers
  end

  def door_near(pos, r)
    @grid.blocker_near(pos, r)
  end

  def door_idx(kind)
    @grid.blocker_index(kind)
  end

  def open_door(n)
    @grid.unseal(n)
  end
end
