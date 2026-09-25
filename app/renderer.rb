# Software 3D renderer: projects textured wall quads, flat shaded meshes and
# glowing billboards into DragonRuby triangle sprites, sorted back to front.
class Renderer
  SCREEN_W   = 1280
  SCREEN_H   = 720
  HALF_W     = 640.0
  HALF_H     = 360.0
  FOCAL      = 620.0
  NEAR       = 0.4
  FOG        = 140.0
  TEX        = 128.0
  TAN_X      = HALF_W / FOCAL
  TAN_Y      = HALF_H / FOCAL
  WHITE      = 'sprites/game/white.png'
  GLOW       = 'sprites/game/glow.png'

  attr_accessor :level
  attr_reader :triangle_count, :last_visible

  def initialize(level)
    @level = level
    @stamp = 0
    @visited = nil
  end

  # ---------------------------------------------------------------- camera

  def begin_frame(pos, right, up, fwd, lights, ambient_boost)
    @px, @py, @pz = pos
    @rx, @ry, @rz = right
    @ux, @uy, @uz = up
    @fx, @fy, @fz = fwd
    @lights = lights
    @boost = ambient_boost # [r, g, b] added to every wall (alarm flashes etc.)
    @list = []
    @triangle_count = 0
  end

  # World point -> camera space.
  def to_cam(x, y, z)
    dx = x - @px
    dy = y - @py
    dz = z - @pz
    [dx * @rx + dy * @ry + dz * @rz,
     dx * @ux + dy * @uy + dz * @uz,
     dx * @fx + dy * @fy + dz * @fz]
  end

  # World direction -> camera space (rotation only).
  def dir_to_cam(x, y, z)
    [x * @rx + y * @ry + z * @rz,
     x * @ux + y * @uy + z * @uz,
     x * @fx + y * @fy + z * @fz]
  end

  # ---------------------------------------------------------------- level

  # Breadth first walk through open cells, only crossing cell boundaries
  # (portals) that are inside the view frustum and within fog distance.
  def visible_cells
    l = @level
    nx = l.nx
    nxy = l.nx * l.ny
    if @visited.nil? || @visited.size != l.cells.size
      @visited = Array.new(l.cells.size, 0)
      gp = (l.nx + 1) * (l.ny + 1) * (l.nz + 1)
      @gp_stamp = Array.new(gp, 0)
      @gp_cam = Array.new(gp)
    end
    @stamp += 1
    stamp = @stamp
    max_d2 = (FOG + CS)**2
    ci = (@px / CS).floor
    cj = (@py / CS).floor
    ck = (@pz / CS).floor
    queue = [[ci, cj, ck]]
    @visited[ci + nx * cj + nxy * ck] = stamp
    result = []
    head = 0
    cells = l.cells
    while head < queue.size
      i, j, k = queue[head]
      head += 1
      n = i + nx * j + nxy * k
      result << n if cells[n]
      Level::DIRS.each_with_index do |d, di|
        ni = i + d[0]
        nj = j + d[1]
        nk = k + d[2]
        m = ni + nx * nj + nxy * nk
        next if @visited[m] == stamp || !l.open?(ni, nj, nk)
        ddx = (ni + 0.5) * CS - @px
        ddy = (nj + 0.5) * CS - @py
        ddz = (nk + 0.5) * CS - @pz
        next if ddx * ddx + ddy * ddy + ddz * ddz > max_d2
        next unless portal_visible?(i, j, k, di)
        @visited[m] = stamp
        queue << [ni, nj, nk]
      end
    end
    result
  end

  PORTALS = [
    [[0, 0, 0], [0, 1, 0], [0, 0, 1], [0, 1, 1]],
    [[1, 0, 0], [1, 1, 0], [1, 0, 1], [1, 1, 1]],
    [[0, 0, 0], [1, 0, 0], [0, 0, 1], [1, 0, 1]],
    [[0, 1, 0], [1, 1, 0], [0, 1, 1], [1, 1, 1]],
    [[0, 0, 0], [1, 0, 0], [0, 1, 0], [1, 1, 0]],
    [[0, 0, 1], [1, 0, 1], [0, 1, 1], [1, 1, 1]]
  ]

  # Camera space position of grid corner (i, j, k), cached per frame.
  def grid_point(i, j, k)
    g = i + (@level.nx + 1) * (j + (@level.ny + 1) * k)
    return @gp_cam[g] if @gp_stamp[g] == @stamp
    @gp_stamp[g] = @stamp
    @gp_cam[g] = to_cam(i * CS, j * CS, k * CS)
  end

  def portal_visible?(i, j, k, dir)
    near = left = right = top = bottom = 0
    PORTALS[dir].each do |o|
      cx, cy, cz = grid_point(i + o[0], j + o[1], k + o[2])
      near += 1 if cz < NEAR
      right += 1 if cx > cz * TAN_X
      left += 1 if cx < -cz * TAN_X
      top += 1 if cy > cz * TAN_Y
      bottom += 1 if cy < -cz * TAN_Y
    end
    near < 4 && left < 4 && right < 4 && top < 4 && bottom < 4
  end

  def draw_level
    faces = @level.faces
    @last_visible = visible_cells
    @last_visible.each do |n|
      list = faces[n]
      next unless list
      list.each { |f| draw_face(f) }
    end
  end

  def draw_face(f)
    nrm = f.normal
    c0 = f.c0
    # back face culling
    return if (@px - c0[0]) * nrm[0] + (@py - c0[1]) * nrm[1] + (@pz - c0[2]) * nrm[2] <= 0

    ctr = f.center
    d = Math.sqrt((ctr[0] - @px)**2 + (ctr[1] - @py)**2 + (ctr[2] - @pz)**2)
    return if d > FOG + CS

    # Subdivide close faces to hide affine texture warping and sorting errors.
    sub = d < 14 ? 4 : (d < 30 ? 3 : (d < 60 ? 2 : 1))
    eu = f.eu
    ev = f.ev
    o = to_cam(c0[0], c0[1], c0[2])
    u = dir_to_cam(eu[0], eu[1], eu[2])
    v = dir_to_cam(ev[0], ev[1], ev[2])

    # Quick frustum reject of the whole face.
    corners = [o,
               [o[0] + u[0], o[1] + u[1], o[2] + u[2]],
               [o[0] + u[0] + v[0], o[1] + u[1] + v[1], o[2] + u[2] + v[2]],
               [o[0] + v[0], o[1] + v[1], o[2] + v[2]]]
    return if corners.all? { |c| c[2] < NEAR }
    return if corners.all? { |c| c[0] > c[2] * TAN_X }
    return if corners.all? { |c| c[0] < -c[2] * TAN_X }
    return if corners.all? { |c| c[1] > c[2] * TAN_Y }
    return if corners.all? { |c| c[1] < -c[2] * TAN_Y }

    shade = f.shade
    path = f.path
    step = 1.0 / sub
    tstep = TEX / sub
    sub.times do |a|
      sa = a * step
      sa1 = sa + step
      sub.times do |b|
        tb = b * step
        tb1 = tb + step
        p0 = [o[0] + u[0] * sa + v[0] * tb, o[1] + u[1] * sa + v[1] * tb, o[2] + u[2] * sa + v[2] * tb, a * tstep, b * tstep]
        p1 = [o[0] + u[0] * sa1 + v[0] * tb, o[1] + u[1] * sa1 + v[1] * tb, o[2] + u[2] * sa1 + v[2] * tb, (a + 1) * tstep, b * tstep]
        p2 = [o[0] + u[0] * sa1 + v[0] * tb1, o[1] + u[1] * sa1 + v[1] * tb1, o[2] + u[2] * sa1 + v[2] * tb1, (a + 1) * tstep, (b + 1) * tstep]
        p3 = [o[0] + u[0] * sa + v[0] * tb1, o[1] + u[1] * sa + v[1] * tb1, o[2] + u[2] * sa + v[2] * tb1, a * tstep, (b + 1) * tstep]

        # sub face centre in world space, for lighting and sorting
        sm = sa + step * 0.5
        tm = tb + step * 0.5
        wx = c0[0] + eu[0] * sm + ev[0] * tm
        wy = c0[1] + eu[1] * sm + ev[1] * tm
        wz = c0[2] + eu[2] * sm + ev[2] * tm
        dd = (wx - @px)**2 + (wy - @py)**2 + (wz - @pz)**2
        r, g, bl = light_at(wx, wy, wz, Math.sqrt(dd), shade)
        emit_textured([p0, p1, p2, p3], path, r, g, bl, dd)
      end
    end
  end

  # Returns 0..255 rgb for a wall point at distance dist from the camera.
  def light_at(x, y, z, dist, tint)
    fog = 1.0 - dist / FOG
    return [0, 0, 0] if fog <= 0
    fog = fog * (0.6 + 0.4 * fog)
    head = dist < 60 ? (1.0 - dist / 60.0) * 0.7 : 0.0
    r = (tint[0] * 1.05 + head) * fog + @boost[0]
    g = (tint[1] * 1.05 + head) * fog + @boost[1]
    b = (tint[2] * 1.05 + head) * fog + @boost[2]
    @lights.each do |lt|
      lx, ly, lz = lt[:pos]
      rad = lt[:radius]
      d2 = (lx - x)**2 + (ly - y)**2 + (lz - z)**2
      next if d2 >= rad * rad
      k = (1.0 - Math.sqrt(d2) / rad) * lt[:intensity]
      c = lt[:color]
      r += c[0] * k
      g += c[1] * k
      b += c[2] * k
    end
    [clamp(r * 255, 0, 255), clamp(g * 255, 0, 255), clamp(b * 255, 0, 255)]
  end

  # poly: camera space points [x, y, z, u, v]
  def emit_textured(poly, path, r, g, b, key)
    poly = clip_near(poly) if poly.any? { |p| p[2] < NEAR }
    return if poly.size < 3
    pts = poly.map do |p|
      iz = FOCAL / p[2]
      [HALF_W + p[0] * iz, HALF_H + p[1] * iz, p[3], p[4]]
    end
    return if offscreen?(pts)
    pad!(pts)
    a = pts[0]
    (1...pts.size - 1).each do |n|
      b1 = pts[n]
      c1 = pts[n + 1]
      @triangle_count += 1
      @list << [key, {
        x: a[0], y: a[1], x2: b1[0], y2: b1[1], x3: c1[0], y3: c1[1],
        source_x: a[2], source_y: a[3],
        source_x2: b1[2], source_y2: b1[3],
        source_x3: c1[2], source_y3: c1[3],
        path: path, r: r, g: g, b: b
      }]
    end
  end

  # Pushes projected vertices ~0.7px away from the polygon centre so that
  # neighbouring triangles overlap instead of leaving hairline cracks.
  def pad!(pts)
    cx = 0.0
    cy = 0.0
    pts.each do |p|
      cx += p[0]
      cy += p[1]
    end
    cx /= pts.size
    cy /= pts.size
    pts.each do |p|
      dx = p[0] - cx
      dy = p[1] - cy
      l = Math.sqrt(dx * dx + dy * dy)
      next if l < 1e-3
      p[0] += dx / l * 0.7
      p[1] += dy / l * 0.7
    end
  end

  def clip_near(poly)
    out = []
    n = poly.size
    n.times do |i|
      a = poly[i]
      b = poly[(i + 1) % n]
      ain = a[2] >= NEAR
      bin = b[2] >= NEAR
      out << a if ain
      next if ain == bin
      t = (NEAR - a[2]) / (b[2] - a[2])
      out << [a[0] + (b[0] - a[0]) * t,
              a[1] + (b[1] - a[1]) * t,
              NEAR,
              a[3] + (b[3] - a[3]) * t,
              a[4] + (b[4] - a[4]) * t]
    end
    out
  end

  def offscreen?(pts)
    pts.all? { |p| p[0] < 0 } || pts.all? { |p| p[0] > SCREEN_W } ||
      pts.all? { |p| p[1] < 0 } || pts.all? { |p| p[1] > SCREEN_H }
  end

  # ---------------------------------------------------------------- meshes

  # Draws a mesh at pos with the given orientation basis. light is the [r,g,b]
  # ambient of the cell the object is in. flash (0..1) blends towards white.
  def draw_mesh(mesh, pos, right, up, fwd, scale, light, flash = 0.0)
    o = to_cam(pos[0], pos[1], pos[2])
    return if o[2] < -mesh.radius * scale
    rc = dir_to_cam(right[0] * scale, right[1] * scale, right[2] * scale)
    uc = dir_to_cam(up[0] * scale, up[1] * scale, up[2] * scale)
    fc = dir_to_cam(fwd[0] * scale, fwd[1] * scale, fwd[2] * scale)
    cam_verts = mesh.verts.map do |p|
      [o[0] + rc[0] * p[0] + uc[0] * p[1] + fc[0] * p[2],
       o[1] + rc[1] * p[0] + uc[1] * p[1] + fc[1] * p[2],
       o[2] + rc[2] * p[0] + uc[2] * p[1] + fc[2] * p[2]]
    end
    dist = Math.sqrt(o[0] * o[0] + o[1] * o[1] + o[2] * o[2])
    fog = 1.0 - dist / FOG
    return if fog <= 0
    fog = fog * 0.7 + 0.3
    inv_s = 1.0 / scale
    mesh.tris.each do |t|
      a = cam_verts[t.a]
      b = cam_verts[t.b]
      c = cam_verts[t.c]
      next if a[2] < NEAR || b[2] < NEAR || c[2] < NEAR
      n = t.normal
      ncx = (rc[0] * n[0] + uc[0] * n[1] + fc[0] * n[2]) * inv_s
      ncy = (rc[1] * n[0] + uc[1] * n[1] + fc[1] * n[2]) * inv_s
      ncz = (rc[2] * n[0] + uc[2] * n[1] + fc[2] * n[2]) * inv_s
      facing = -(a[0] * ncx + a[1] * ncy + a[2] * ncz)
      next if facing <= 0 && !t.double_sided
      mx = (a[0] + b[0] + c[0]) / 3.0
      my = (a[1] + b[1] + c[1]) / 3.0
      mz = (a[2] + b[2] + c[2]) / 3.0
      ml = Math.sqrt(mx * mx + my * my + mz * mz) + 1e-6
      lambert = facing.abs / ml
      s = (0.35 + 0.75 * lambert) * fog
      col = t.color
      emissive = t.emissive
      r = col[0] * (emissive ? 1.0 : s * (light[0] * 0.5 + 0.6))
      g = col[1] * (emissive ? 1.0 : s * (light[1] * 0.5 + 0.6))
      bb = col[2] * (emissive ? 1.0 : s * (light[2] * 0.5 + 0.6))
      if flash > 0
        r += (255 - r) * flash
        g += (255 - g) * flash
        bb += (255 - bb) * flash
      end
      ia = FOCAL / a[2]
      ib = FOCAL / b[2]
      ic = FOCAL / c[2]
      @triangle_count += 1
      @list << [mx * mx + my * my + mz * mz, {
        x: HALF_W + a[0] * ia, y: HALF_H + a[1] * ia,
        x2: HALF_W + b[0] * ib, y2: HALF_H + b[1] * ib,
        x3: HALF_W + c[0] * ic, y3: HALF_H + c[1] * ic,
        source_x: 0, source_y: 0, source_x2: 8, source_y2: 0, source_x3: 0, source_y3: 8,
        path: WHITE, r: clamp(r, 0, 255), g: clamp(g, 0, 255), b: clamp(bb, 0, 255)
      }]
    end
  end

  # ---------------------------------------------------------------- sprites

  def draw_glow(pos, size, r, g, b, a = 255, path = GLOW)
    c = to_cam(pos[0], pos[1], pos[2])
    return if c[2] < NEAR
    s = size * FOCAL / c[2]
    return if s < 0.5
    sx = HALF_W + c[0] * FOCAL / c[2]
    sy = HALF_H + c[1] * FOCAL / c[2]
    return if sx < -s || sx > SCREEN_W + s || sy < -s || sy > SCREEN_H + s
    d2 = c[0] * c[0] + c[1] * c[1] + c[2] * c[2]
    @list << [d2 - size * size, {
      x: sx - s * 0.5, y: sy - s * 0.5, w: s, h: s, path: path,
      r: r, g: g, b: b, a: a, blendmode_enum: 2
    }]
  end

  # Projects a world point to screen coordinates (nil if behind the camera).
  def project(pos)
    c = to_cam(pos[0], pos[1], pos[2])
    return nil if c[2] < NEAR
    [HALF_W + c[0] * FOCAL / c[2], HALF_H + c[1] * FOCAL / c[2], c[2]]
  end

  def flush(outputs, dx = 0, dy = 0)
    sorted = @list.sort_by { |e| -e[0] }
    if dx != 0 || dy != 0
      sorted.each do |e|
        h = e[1]
        h[:x] += dx
        h[:y] += dy
        if h[:x2]
          h[:x2] += dx
          h[:y2] += dy
          h[:x3] += dx
          h[:y3] += dy
        end
      end
    end
    outputs.sprites << sorted.map { |e| e[1] }
  end
end
