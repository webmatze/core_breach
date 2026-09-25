# The mine is a 3D grid of cube segments. Open cells can be flown through,
# solid cells are rock. Wall faces are generated wherever an open cell touches
# a solid one.
CS = 10.0 # cell size in world units

TEXTURES = {
  rock:      'sprites/game/rock.png',
  rock_dark: 'sprites/game/rock_dark.png',
  lava:      'sprites/game/lava_rock.png',
  metal:     'sprites/game/metal.png',
  tech:      'sprites/game/tech.png',
  grate:     'sprites/game/grate.png',
  door_blue: 'sprites/game/door_blue.png',
  door_red:  'sprites/game/door_red.png',
  door_exit: 'sprites/game/grate.png'
}

# One wall quad: corner c0 plus edge vectors eu (c0 -> c1) and ev (c0 -> c3).
class Face
  attr_reader :normal, :c0, :eu, :ev, :center, :path, :shade, :cell

  def initialize(normal, c0, eu, ev, path, shade, cell)
    @normal = normal
    @c0 = c0
    @eu = eu
    @ev = ev
    @center = [c0[0] + (eu[0] + ev[0]) * 0.5,
               c0[1] + (eu[1] + ev[1]) * 0.5,
               c0[2] + (eu[2] + ev[2]) * 0.5]
    @path = path
    @shade = shade
    @cell = cell
  end
end

class Level
  # [di, dj, dk] for the six neighbours
  DIRS = [[-1, 0, 0], [1, 0, 0], [0, -1, 0], [0, 1, 0], [0, 0, -1], [0, 0, 1]]
  # Floors are lit a little brighter than walls, ceilings darker. Gives depth cues.
  DIR_SHADE = [0.82, 0.82, 1.0, 0.62, 0.74, 0.74]

  attr_reader :nx, :ny, :nz, :cells, :faces, :doors, :spawns, :player_start, :exit_cells, :reactor_pos

  def initialize
    @nx = 48
    @ny = 16
    @nz = 48
    size = @nx * @ny * @nz
    @cells = Array.new(size, false)
    @tex = Array.new(size, :rock)
    @tint = Array.new(size, [0.7, 0.7, 0.7])
    @doors = {}
    @spawns = []
    @exit_cells = {}
    LevelData.build(self)
    rebuild_faces
  end

  # ----------------------------------------------------------- construction

  def idx(i, j, k)
    i + @nx * (j + @ny * k)
  end

  def coords(idx)
    i = idx % @nx
    j = idx.idiv(@nx) % @ny
    k = idx.idiv(@nx * @ny)
    [i, j, k]
  end

  def in_bounds?(i, j, k)
    i > 0 && j > 0 && k > 0 && i < @nx - 1 && j < @ny - 1 && k < @nz - 1
  end

  def carve(i0, i1, j0, j1, k0, k1, tex, tint)
    (k0..k1).each do |k|
      (j0..j1).each do |j|
        (i0..i1).each do |i|
          next unless in_bounds?(i, j, k)
          n = idx(i, j, k)
          @cells[n] = true
          @tex[n] = tex
          @tint[n] = tint
        end
      end
    end
  end

  def fill(i0, i1, j0, j1, k0, k1)
    (k0..k1).each do |k|
      (j0..j1).each do |j|
        (i0..i1).each do |i|
          @cells[idx(i, j, k)] = false if in_bounds?(i, j, k)
        end
      end
    end
  end

  # A door is a solid cell with a door texture until it is opened.
  def add_door(i, j, k, kind)
    n = idx(i, j, k)
    @cells[n] = false
    @doors[n] = kind
  end

  def mark_exit(i, j, k)
    @exit_cells[idx(i, j, k)] = true
  end

  def set_reactor(pos)
    @reactor_pos = pos
  end

  def set_player_start(pos)
    @player_start = pos
  end

  def spawn(kind, i, j, k)
    @spawns << [kind, cell_center(i, j, k)]
  end

  # Randomly raises floor cells / lowers ceiling cells inside a room so caverns
  # look less boxy. Never touches cells next to doors or openings in the floor.
  def roughen(i0, i1, j0, j1, k0, k1, count, rng)
    count.times do
      i = rng.int(i0 + 1, i1 - 1)
      k = rng.int(k0 + 1, k1 - 1)
      h = rng.int(1, 2)
      if rng.next_f < 0.5
        next if open?(i, j0 - 1, k) || @doors[idx(i, j0 - 1, k)]
        fill(i, i, j0, j0 + h - 1, k, k)
      else
        next if open?(i, j1 + 1, k) || @doors[idx(i, j1 + 1, k)]
        fill(i, i, j1 - h + 1, j1, k, k)
      end
    end
  end

  def cell_center(i, j, k)
    [(i + 0.5) * CS, (j + 0.5) * CS, (k + 0.5) * CS]
  end

  # ----------------------------------------------------------- queries

  def open?(i, j, k)
    return false if i < 0 || j < 0 || k < 0 || i >= @nx || j >= @ny || k >= @nz
    @cells[i + @nx * (j + @ny * k)]
  end

  def cell_of(p)
    [(p[0] / CS).floor, (p[1] / CS).floor, (p[2] / CS).floor]
  end

  def solid_at?(p)
    !open?((p[0] / CS).floor, (p[1] / CS).floor, (p[2] / CS).floor)
  end

  def tint_of(n)
    @tint[n]
  end

  def tint_at(p)
    i, j, k = cell_of(p)
    return [0.5, 0.5, 0.5] unless open?(i, j, k)
    @tint[idx(i, j, k)]
  end

  def exit_at?(p)
    i, j, k = cell_of(p)
    @exit_cells[idx(i, j, k)]
  end

  # Line of sight by sampling along the segment.
  def los?(a, b, step = 2.0)
    d = V.dist(a, b)
    n = (d / step).ceil
    return true if n <= 1
    dx = (b[0] - a[0]) / n
    dy = (b[1] - a[1]) / n
    dz = (b[2] - a[2]) / n
    x = a[0]
    y = a[1]
    z = a[2]
    (n - 1).times do
      x += dx
      y += dy
      z += dz
      return false unless open?((x / CS).floor, (y / CS).floor, (z / CS).floor)
    end
    true
  end

  # Pushes a sphere out of solid cells. Mutates pos and returns the last
  # collision normal (or nil).
  def collide_sphere(pos, r)
    hit = nil
    i0 = ((pos[0] - r) / CS).floor
    i1 = ((pos[0] + r) / CS).floor
    j0 = ((pos[1] - r) / CS).floor
    j1 = ((pos[1] + r) / CS).floor
    k0 = ((pos[2] - r) / CS).floor
    k1 = ((pos[2] + r) / CS).floor
    rr = r * r
    (k0..k1).each do |k|
      (j0..j1).each do |j|
        (i0..i1).each do |i|
          next if open?(i, j, k)
          cx = clamp(pos[0], i * CS, (i + 1) * CS)
          cy = clamp(pos[1], j * CS, (j + 1) * CS)
          cz = clamp(pos[2], k * CS, (k + 1) * CS)
          dx = pos[0] - cx
          dy = pos[1] - cy
          dz = pos[2] - cz
          d2 = dx * dx + dy * dy + dz * dz
          next if d2 >= rr || d2 < 1e-9
          d = Math.sqrt(d2)
          push = r - d
          nx = dx / d
          ny = dy / d
          nz = dz / d
          pos[0] += nx * push
          pos[1] += ny * push
          pos[2] += nz * push
          hit = [nx, ny, nz]
        end
      end
    end
    hit
  end

  # Returns the door cell index touching the sphere, if any.
  def door_near(pos, r)
    i0 = ((pos[0] - r) / CS).floor
    i1 = ((pos[0] + r) / CS).floor
    j0 = ((pos[1] - r) / CS).floor
    j1 = ((pos[1] + r) / CS).floor
    k0 = ((pos[2] - r) / CS).floor
    k1 = ((pos[2] + r) / CS).floor
    (k0..k1).each do |k|
      (j0..j1).each do |j|
        (i0..i1).each do |i|
          n = idx(i, j, k)
          return n if @doors[n]
        end
      end
    end
    nil
  end

  def open_door(n)
    return unless @doors.delete(n)
    @cells[n] = true
    i, j, k = coords(n)
    DIRS.each do |d|
      m = idx(i + d[0], j + d[1], k + d[2])
      if @cells[m]
        @tex[n] = @tex[m]
        @tint[n] = @tint[m]
        break
      end
    end
    rebuild_faces
  end

  def door_idx(kind)
    @doors.each { |n, v| return n if v == kind }
    nil
  end

  # ----------------------------------------------------------- faces

  def rebuild_faces
    @faces = Array.new(@cells.size)
    (1...@nz - 1).each do |k|
      (1...@ny - 1).each do |j|
        (1...@nx - 1).each do |i|
          n = idx(i, j, k)
          next unless @cells[n]
          list = []
          DIRS.each_with_index do |d, di|
            m = idx(i + d[0], j + d[1], k + d[2])
            next if @cells[m]
            door = @doors[m]
            tex = if door
                    TEXTURES[:"door_#{door}"]
                  elsif @exit_cells[n]
                    TEXTURES[:grate]
                  else
                    TEXTURES[@tex[n]]
                  end
            list << make_face(i, j, k, di, tex, n)
          end
          @faces[n] = list unless list.empty?
        end
      end
    end
  end

  def make_face(i, j, k, dir, tex, n)
    x0 = i * CS
    y0 = j * CS
    z0 = k * CS
    x1 = x0 + CS
    y1 = y0 + CS
    z1 = z0 + CS
    c = case dir
        when 0 then [[x0, y0, z0], [x0, y0, z1], [x0, y1, z0], [1, 0, 0]]
        when 1 then [[x1, y0, z1], [x1, y0, z0], [x1, y1, z1], [-1, 0, 0]]
        when 2 then [[x0, y0, z0], [x1, y0, z0], [x0, y0, z1], [0, 1, 0]]
        when 3 then [[x0, y1, z1], [x1, y1, z1], [x0, y1, z0], [0, -1, 0]]
        when 4 then [[x1, y0, z0], [x0, y0, z0], [x1, y1, z0], [0, 0, 1]]
        else        [[x0, y0, z1], [x1, y0, z1], [x0, y1, z1], [0, 0, -1]]
        end
    c0 = c[0]
    tint = @tint[n]
    shade = DIR_SHADE[dir]
    Face.new(c[3], c0, V.sub(c[1], c0), V.sub(c[2], c0), tex,
             [tint[0] * shade, tint[1] * shade, tint[2] * shade], n)
  end
end
