# Rotatable 3D wireframe map of the parts of the mine the player has seen.
# Only the outline edges of walls are drawn: an edge is skipped when the wall
# simply continues flat into the neighbouring cell.
class Automap
  FOCAL = 620.0
  NEAR = 1.0
  EXPLORE_RADIUS = 100.0
  DOOR_COLORS = { blue: [70, 130, 255], red: [255, 70, 70], exit: [90, 255, 120] }

  def initialize(level)
    @level = level
    @explored = Array.new(level.cells.size, false)
    @explored_list = []
    @edges = {}
    @door_count = level.doors.size
    @yaw = 0.0
    @pitch = 0.5
    @dist = 120.0
  end

  def explored?(pos)
    i, j, k = @level.cell_of(pos)
    @level.open?(i, j, k) && @explored[@level.idx(i, j, k)]
  end

  # Marks visible cells near the camera as explored.
  def explore(cells, cam)
    r2 = EXPLORE_RADIUS * EXPLORE_RADIUS
    cells.each do |n|
      next if @explored[n]
      i, j, k = @level.coords(n)
      dx = (i + 0.5) * CS - cam[0]
      dy = (j + 0.5) * CS - cam[1]
      dz = (k + 0.5) * CS - cam[2]
      next if dx * dx + dy * dy + dz * dz > r2
      @explored[n] = true
      @explored_list << n
      add_cell_edges(i, j, k)
    end
  end

  # ------------------------------------------------------------- edges

  def rebuild
    @edges = {}
    @explored_list.each do |n|
      next unless @level.cells[n]
      i, j, k = @level.coords(n)
      add_cell_edges(i, j, k)
    end
  end

  def wall_kind(c)
    @level.doors[@level.idx(c[0], c[1], c[2])] || :wall
  end

  def open_at?(c)
    @level.open?(c[0], c[1], c[2])
  end

  def add_cell_edges(i, j, k)
    c = [i, j, k]
    n = @level.idx(i, j, k)
    base = @level.exit_cells[n] ? DOOR_COLORS[:exit] : @level.tint_of(n).map { |t| clamp(t * 190, 40, 230) }
    Level::DIRS.each_with_index do |d, di|
      nb = [i + d[0], j + d[1], k + d[2]]
      next if open_at?(nb)
      axis = di.idiv(2)
      sign = d[axis]
      plane = c[axis] + (sign > 0 ? 1 : 0)
      kind = wall_kind(nb)
      color = kind == :wall ? base : DOOR_COLORS[kind]
      others = [0, 1, 2] - [axis]
      others.each do |a|
        b = a == others[0] ? others[1] : others[0]
        [-1, 1].each do |s|
          side = c.dup
          side[a] += s
          if open_at?(side)
            beyond = side.dup
            beyond[axis] += sign
            next if !open_at?(beyond) && wall_kind(beyond) == kind
          end
          p1 = [0, 0, 0]
          p1[axis] = plane
          p1[a] = c[a] + (s > 0 ? 1 : 0)
          p1[b] = c[b]
          p2 = p1.dup
          p2[b] += 1
          add_edge(p1, p2, color, kind != :wall)
        end
      end
    end
  end

  def add_edge(p1, p2, color, priority)
    g1 = grid_key(p1)
    g2 = grid_key(p2)
    key = g1 < g2 ? g1 * 100_000 + g2 : g2 * 100_000 + g1
    existing = @edges[key]
    return if existing && !priority
    @edges[key] = [p1.map { |v| v * CS }, p2.map { |v| v * CS }, color]
  end

  def grid_key(p)
    p[0] + (@level.nx + 1) * (p[1] + (@level.ny + 1) * p[2])
  end

  # ------------------------------------------------------------- view

  def open(ship)
    rebuild if @level.doors.size != @door_count
    @door_count = @level.doors.size
    @yaw = Math.atan2(ship.fwd[0], ship.fwd[2])
    @pitch = 0.5
    @dist = 120.0
  end

  def update(inputs)
    kb = inputs.keyboard
    ms = inputs.mouse
    pad = inputs.controller_one
    @yaw += (ms.relative_x || 0) * 0.006
    @pitch -= (ms.relative_y || 0) * 0.006
    @yaw -= 0.03 if kb.left_arrow || kb.a
    @yaw += 0.03 if kb.right_arrow || kb.d
    @pitch += 0.03 if kb.up_arrow
    @pitch -= 0.03 if kb.down_arrow
    rx = pad.right_analog_x_perc || 0
    ry = pad.right_analog_y_perc || 0
    @yaw += rx * 0.04 if rx.abs > 0.15
    @pitch -= ry * 0.04 if ry.abs > 0.15
    @dist -= 3 if kb.w || pad.r1
    @dist += 3 if kb.s || pad.l1
    wheel = ms.wheel
    @dist -= wheel.y * 12 if wheel
    @pitch = clamp(@pitch, -1.45, 1.45)
    @dist = clamp(@dist, 25.0, 450.0)
  end

  def render(outputs, ship, markers)
    target = ship.pos
    cp = Math.cos(@pitch)
    fwd = [Math.sin(@yaw) * cp, -Math.sin(@pitch), Math.cos(@yaw) * cp]
    right, up = V.basis_from_forward(fwd)
    cam = V.madd(target, fwd, -@dist)
    @cam = cam
    @right = right
    @up = up
    @fwd = fwd
    fade_range = @dist + 250.0

    lines = []
    @edges.each_value do |p1, p2, color|
      seg = project_segment(p1, p2)
      next unless seg
      f = clamp(1.3 - seg[4] / fade_range, 0.25, 1.0)
      lines << { x: seg[0], y: seg[1], x2: seg[2], y2: seg[3],
                 r: color[0] * f, g: color[1] * f, b: color[2] * f }
    end

    markers.each do |pos, color, size|
      diamond(lines, pos, size, color)
    end
    ship_marker(lines, ship)
    outputs.lines << lines
  end

  def project_segment(p1, p2)
    a = to_cam(p1)
    b = to_cam(p2)
    return nil if a[2] < NEAR && b[2] < NEAR
    if a[2] < NEAR
      a = clip(b, a)
    elsif b[2] < NEAR
      b = clip(a, b)
    end
    [640 + a[0] * FOCAL / a[2], 360 + a[1] * FOCAL / a[2],
     640 + b[0] * FOCAL / b[2], 360 + b[1] * FOCAL / b[2],
     (a[2] + b[2]) * 0.5]
  end

  def clip(inside, outside)
    t = (NEAR - inside[2]) / (outside[2] - inside[2])
    [inside[0] + (outside[0] - inside[0]) * t, inside[1] + (outside[1] - inside[1]) * t, NEAR]
  end

  def to_cam(p)
    d = V.sub(p, @cam)
    [V.dot(d, @right), V.dot(d, @up), V.dot(d, @fwd)]
  end

  def line3(lines, p1, p2, color)
    seg = project_segment(p1, p2)
    return unless seg
    lines << { x: seg[0], y: seg[1], x2: seg[2], y2: seg[3], r: color[0], g: color[1], b: color[2] }
  end

  def diamond(lines, pos, s, color)
    pts = [[s, 0, 0], [0, s, 0], [-s, 0, 0], [0, -s, 0], [0, 0, s], [0, 0, -s]].map { |o| V.add(pos, o) }
    [[0, 1], [1, 2], [2, 3], [3, 0], [0, 4], [1, 4], [2, 4], [3, 4], [0, 5], [1, 5], [2, 5], [3, 5]].each do |a, b|
      line3(lines, pts[a], pts[b], color)
    end
  end

  def ship_marker(lines, ship)
    p = ship.pos
    nose = V.madd(p, ship.fwd, 5)
    tail = V.madd(p, ship.fwd, -3)
    l = V.madd(tail, ship.right, -3)
    r = V.madd(tail, ship.right, 3)
    top = V.madd(tail, ship.up, 2)
    color = [255, 230, 60]
    [[nose, l], [nose, r], [l, r], [nose, top], [l, top], [r, top]].each do |a, b|
      line3(lines, a, b, color)
    end
  end
end
