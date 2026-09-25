module D3D
  # Software renderer for 6DOF scenes: textured CellGrid walls, flat shaded
  # FlatMesh objects and additive glow billboards, all emitted as DragonRuby
  # triangle/rect sprites and sorted back to front (painter's algorithm).
  #
  # Per frame:
  #   renderer.begin_frame(pose, lights: [...])
  #   renderer.draw_grid(grid)
  #   renderer.draw_mesh(...) / renderer.draw_glow(...)
  #   renderer.flush(args.outputs)
  #
  # Features: portal flood-fill visibility (via CellGrid#visible_cells),
  # near-plane clipping with UV interpolation, distance based subdivision to
  # hide affine texture warping, fog, a camera headlight, coloured point lights
  # and sub-pixel seam padding.
  class SceneRenderer
    # materials: { symbol => { path: 'sprites/x.png', size: 128 } } used by grid faces.
    # lights passed to begin_frame: [{ pos: [x,y,z], radius:, color: [r,g,b] (0..1), intensity: }]
    attr_reader :width, :height, :focal, :near, :fog, :tan_x, :tan_y,
                :triangle_count, :last_visible, :camera_position
    attr_accessor :materials

    def initialize(width: 1280, height: 720, focal: nil, fov: 92.0, near: 0.4, fog: 140.0,
                   headlight_range: 60.0, headlight: 0.7, ambient_scale: 1.05,
                   materials: {}, white_path: 'sprites/d3d/white.png', white_size: 8,
                   glow_path: 'sprites/d3d/glow.png')
      @width = width
      @height = height
      @half_w = width / 2.0
      @half_h = height / 2.0
      @focal = (focal || @half_w / Math.tan(fov * Math::PI / 360.0)).to_f
      @tan_x = @half_w / @focal
      @tan_y = @half_h / @focal
      @near = near.to_f
      @fog = fog.to_f
      @headlight_range = headlight_range.to_f
      @headlight = headlight.to_f
      @ambient_scale = ambient_scale
      @materials = materials
      @white_path = white_path
      @white_size = white_size
      @glow_path = glow_path
      @list = []
      @triangle_count = 0
      @last_visible = []
      @camera_position = [0.0, 0.0, 0.0]
    end

    # ---------------------------------------------------------------- camera

    # pose: anything with position/right/up/fwd arrays (e.g. D3D::Pose).
    # ambient_boost: [r, g, b] added to every wall (alarm flashes etc.).
    def begin_frame(pose, lights: [], ambient_boost: [0.0, 0.0, 0.0])
      @camera_position = pose.position
      @px, @py, @pz = pose.position
      @rx, @ry, @rz = pose.right
      @ux, @uy, @uz = pose.up
      @fx, @fy, @fz = pose.fwd
      @lights = lights
      @boost = ambient_boost
      @list = []
      @triangle_count = 0
      self
    end

    # World point -> camera space [x right, y up, z forward].
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

    # Projects a world point to [screen_x, screen_y, depth], or nil if behind the camera.
    def project(pos)
      c = to_cam(pos[0], pos[1], pos[2])
      return nil if c[2] < @near
      [@half_w + c[0] * @focal / c[2], @half_h + c[1] * @focal / c[2], c[2]]
    end

    # ---------------------------------------------------------------- grid

    def draw_grid(grid)
      faces = grid.faces
      @last_visible = grid.visible_cells(self)
      @last_visible.each do |n|
        list = faces[n]
        next unless list
        list.each { |f| draw_face(f) }
      end
      self
    end

    # Draws one CellFace (or anything with normal/c0/eu/ev/center/material/shade).
    def draw_face(f)
      nrm = f.normal
      c0 = f.c0
      # back face culling
      return if (@px - c0[0]) * nrm[0] + (@py - c0[1]) * nrm[1] + (@pz - c0[2]) * nrm[2] <= 0

      ctr = f.center
      d = Math.sqrt((ctr[0] - @px)**2 + (ctr[1] - @py)**2 + (ctr[2] - @pz)**2)
      return if d > @fog + 10

      mat = @materials[f.material]
      return unless mat
      tex = mat[:size] || 128

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
      return if corners.all? { |c| c[2] < @near }
      return if corners.all? { |c| c[0] > c[2] * @tan_x }
      return if corners.all? { |c| c[0] < -c[2] * @tan_x }
      return if corners.all? { |c| c[1] > c[2] * @tan_y }
      return if corners.all? { |c| c[1] < -c[2] * @tan_y }

      shade = f.shade
      path = mat[:path]
      step = 1.0 / sub
      tstep = tex.to_f / sub
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

    # Returns 0..255 rgb for a surface point at distance dist from the camera.
    def light_at(x, y, z, dist, tint)
      fog = 1.0 - dist / @fog
      return [0, 0, 0] if fog <= 0
      fog = fog * (0.6 + 0.4 * fog)
      head = dist < @headlight_range ? (1.0 - dist / @headlight_range) * @headlight : 0.0
      r = (tint[0] * @ambient_scale + head) * fog + @boost[0]
      g = (tint[1] * @ambient_scale + head) * fog + @boost[1]
      b = (tint[2] * @ambient_scale + head) * fog + @boost[2]
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
      [D3D.clamp(r * 255, 0, 255), D3D.clamp(g * 255, 0, 255), D3D.clamp(b * 255, 0, 255)]
    end

    # poly: camera space points [x, y, z, u, v]
    def emit_textured(poly, path, r, g, b, key)
      poly = clip_near(poly) if poly.any? { |p| p[2] < @near }
      return if poly.size < 3
      pts = poly.map do |p|
        iz = @focal / p[2]
        [@half_w + p[0] * iz, @half_h + p[1] * iz, p[3], p[4]]
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

    # Sutherland-Hodgman clip of a camera space polygon against z = near,
    # interpolating the u/v texture coordinates of new vertices.
    def clip_near(poly)
      out = []
      n = poly.size
      n.times do |i|
        a = poly[i]
        b = poly[(i + 1) % n]
        ain = a[2] >= @near
        bin = b[2] >= @near
        out << a if ain
        next if ain == bin
        t = (@near - a[2]) / (b[2] - a[2])
        out << [a[0] + (b[0] - a[0]) * t,
                a[1] + (b[1] - a[1]) * t,
                @near,
                a[3] + (b[3] - a[3]) * t,
                a[4] + (b[4] - a[4]) * t]
      end
      out
    end

    def offscreen?(pts)
      pts.all? { |p| p[0] < 0 } || pts.all? { |p| p[0] > @width } ||
        pts.all? { |p| p[1] < 0 } || pts.all? { |p| p[1] > @height }
    end

    # ---------------------------------------------------------------- meshes

    # Draws a FlatMesh at pos with the given orientation basis. light is the
    # [r,g,b] ambient (0..~1.2) around the object. flash (0..1) blends to white.
    def draw_mesh(mesh, pos, right, up, fwd, scale = 1.0, light = [1.0, 1.0, 1.0], flash = 0.0)
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
      fog = 1.0 - dist / @fog
      return if fog <= 0
      fog = fog * 0.7 + 0.3
      inv_s = 1.0 / scale
      ws = @white_size
      mesh.tris.each do |t|
        a = cam_verts[t.a]
        b = cam_verts[t.b]
        c = cam_verts[t.c]
        next if a[2] < @near || b[2] < @near || c[2] < @near
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
        ia = @focal / a[2]
        ib = @focal / b[2]
        ic = @focal / c[2]
        @triangle_count += 1
        @list << [mx * mx + my * my + mz * mz, {
          x: @half_w + a[0] * ia, y: @half_h + a[1] * ia,
          x2: @half_w + b[0] * ib, y2: @half_h + b[1] * ib,
          x3: @half_w + c[0] * ic, y3: @half_h + c[1] * ic,
          source_x: 0, source_y: 0, source_x2: ws, source_y2: 0, source_x3: 0, source_y3: ws,
          path: @white_path,
          r: D3D.clamp(r, 0, 255), g: D3D.clamp(g, 0, 255), b: D3D.clamp(bb, 0, 255)
        }]
      end
      self
    end

    # ---------------------------------------------------------------- sprites

    # Camera facing additive sprite of world size `size` centred on pos.
    def draw_glow(pos, size, r, g, b, a = 255, path: @glow_path)
      c = to_cam(pos[0], pos[1], pos[2])
      return if c[2] < @near
      s = size * @focal / c[2]
      return if s < 0.5
      sx = @half_w + c[0] * @focal / c[2]
      sy = @half_h + c[1] * @focal / c[2]
      return if sx < -s || sx > @width + s || sy < -s || sy > @height + s
      d2 = c[0] * c[0] + c[1] * c[1] + c[2] * c[2]
      @list << [d2 - size * size, {
        x: sx - s * 0.5, y: sy - s * 0.5, w: s, h: s, path: path,
        r: r, g: g, b: b, a: a, blendmode_enum: 2
      }]
      self
    end

    # ---------------------------------------------------------------- output

    # Everything queued this frame, sorted back to front.
    def sorted_primitives
      @list.sort_by { |e| -e[0] }.map { |e| e[1] }
    end

    def flush(outputs)
      outputs.sprites << sorted_primitives
    end
  end
end
