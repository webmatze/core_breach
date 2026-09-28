# A level: a D3D::CellGrid plus the game rules on top of it (key doors, the
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
    door_yellow: { path: 'sprites/game/door_yellow.png', size: 128 },
    door_exit: { path: 'sprites/game/grate.png', size: 128 }
  }
  DOOR_MATERIALS = { blue: :door_blue, yellow: :door_yellow, red: :door_red, exit: :door_exit }

  attr_reader :defn, :grid, :spawns, :player_start, :exit_cells, :reactor_pos, :lamps, :beacons,
              :pylons, :boss_pos, :collapses, :escape_zone

  # defn: a level definition module from Levels::ALL
  def initialize(defn)
    @defn = defn
    nx, ny, nz = defn::SIZE
    @grid = D3D::CellGrid.new(nx, ny, nz, cell_size: CS)
    @spawns = []
    @exit_cells = {}
    @lamps = []
    @beacons = []
    @pylons = []
    @collapses = []
    @escape_zone = nil
    defn.build(self)
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

  def set_boss(pos)
    @boss_pos = pos
  end

  # A shield pylon standing on the floor of open cell (i, j, k).
  def pylon(i, j, k)
    puts "Level #{@defn::TITLE}: pylon at #{[i, j, k]} is not in an open cell" unless @grid.open?(i, j, k)
    puts "Level #{@defn::TITLE}: pylon at #{[i, j, k]} has no floor" if @grid.open?(i, j - 1, k)
    @pylons << [(i + 0.5) * CS, j * CS + Pylon::HALF_HEIGHT + 0.5, (k + 0.5) * CS]
  end

  # Cell (i, j, k) caves in `time` seconds after the countdown starts.
  def collapse(i, j, k, time)
    @collapses << [i, j, k, time.to_f]
  end

  # Collapses only happen while the ship is inside this box of cells, so the
  # player can never be locked out of the escape route.
  def set_escape_zone(i0, i1, j0, j1, k0, k1)
    @escape_zone = [i0, i1, j0, j1, k0, k1]
  end

  def in_escape_zone?(p)
    return true unless @escape_zone
    i0, i1, j0, j1, k0, k1 = @escape_zone
    i, j, k = @grid.cell_of(p)
    i.between?(i0, i1) && j.between?(j0, j1) && k.between?(k0, k1)
  end

  # True if a sphere overlaps cell (i, j, k).
  def sphere_in_cell?(p, r, i, j, k)
    cx = clamp(p[0], i * CS, (i + 1) * CS)
    cy = clamp(p[1], j * CS, (j + 1) * CS)
    cz = clamp(p[2], k * CS, (k + 1) * CS)
    V.dist2(p, [cx, cy, cz]) < r * r
  end

  def set_player_start(pos)
    @player_start = pos
  end

  # A fixed wall lamp at cell coordinates (fractions allowed), lighting the walls
  # around it. color is 0..255 rgb.
  def lamp(i, j, k, color)
    @lamps << { pos: [i * CS, j * CS, k * CS], radius: 65, color: color.map { |c| c / 255.0 },
                intensity: 1.0, rgb: color }
  end

  # A point on the escape route (cell coordinates, fractions allowed). Beacons
  # switch on as pulsing green lights and map markers once the exit opens.
  def beacon(i, j, k)
    @beacons << [i * CS, j * CS, k * CS]
  end

  def spawn(kind, i, j, k)
    @spawns << [kind, @grid.cell_center(i, j, k), nil]
  end

  WALLS = { west: [-1, 0, 0], east: [1, 0, 0], down: [0, -1, 0], up: [0, 1, 0],
            south: [0, 0, -1], north: [0, 0, 1] }

  # A turret mounted on the given wall of open cell (i, j, k).
  def turret(i, j, k, wall)
    d = WALLS[wall]
    unless @grid.open?(i, j, k) && !@grid.open?(i + d[0], j + d[1], k + d[2])
      puts "Level #{@defn::TITLE}: turret at #{[i, j, k]} has no #{wall} wall"
    end
    pos = V.madd(@grid.cell_center(i, j, k), d, CS * 0.5 - 1.0)
    @spawns << [:turret, pos, V.scale(d, -1.0)]
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
