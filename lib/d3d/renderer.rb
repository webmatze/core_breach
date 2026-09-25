module D3D
  module Renderer
    # Pre-computed constants for screen conversion
    HALF_WIDTH = SCREEN_WIDTH * 0.5
    HALF_HEIGHT = SCREEN_HEIGHT * 0.5
    # Pixel size of the voxel block textures (UVs are normalized 0..1)
    VOXEL_TEX_SIZE = 16
    # Triangles entirely beyond this NDC range are skipped
    NDC_MARGIN = 4.0

    class << self
      # light: optional { direction: [x, y, z] (pointing towards the light),
      #   ambient: 0.35 }. Flat shades every triangle by its face normal.
      # fog: optional { near:, far:, color: [r, g, b] }. Blends triangles
      #   towards color with view distance and skips triangles beyond far.
      #   Textures are tinted multiplicatively, so on textured faces the blend
      #   is only exact towards dark fog colours.
      def render(camera, models, lights: nil, light: nil, fog: nil)
        triangles = []

        view_matrix = camera.get_view_matrix
        projection_matrix = camera.get_projection_matrix
        vp_matrix = projection_matrix * view_matrix

        # Camera position for frustum culling
        cam_pos = camera.position
        cam_forward = camera.forward
        near = camera.near
        lit = light_setup(light)
        fogs = fog_setup(fog)

        models.each do |model|
          next unless model.visible

          # Model-level frustum culling: skip models behind camera
          if model_behind_camera?(model, cam_pos, cam_forward)
            next
          end

          model_matrix = model.get_model_matrix
          mvp_matrix = vp_matrix * model_matrix

          render_model_optimized(triangles, model, model_matrix.data, mvp_matrix.data,
                                 cam_pos, near, lit, fogs)
        end

        triangles.sort_by { |t| -t[:z_depth] }
      end

      # Takes the same light:/fog: options as render.
      def render_voxel_world(camera, voxel_world, light: nil, fog: nil)
        mesh_data = voxel_world.build_mesh
        return [] if mesh_data.nil? || mesh_data[:faces].empty?

        triangles = []
        vertices = mesh_data[:vertices]
        faces = mesh_data[:faces]

        view_matrix = camera.get_view_matrix
        projection_matrix = camera.get_projection_matrix
        mvp_matrix = projection_matrix * view_matrix
        mvp = mvp_matrix.data

        cam_pos = camera.position
        px = cam_pos.x
        py = cam_pos.y
        pz = cam_pos.z
        near = camera.near
        lit = light_setup(light)
        fogs = fog_setup(fog)
        fog_far = fogs ? fogs[1] : nil

        faces.each do |face|
          vi = face[:v]
          v0 = vertices[vi[0]]
          v0x, v0y, v0z = v0[0], v0[1], v0[2]

          # Back face culling in world space, before any projection work
          n = face[:n]
          next if (px - v0x) * n[0] + (py - v0y) * n[1] + (pz - v0z) * n[2] <= 0

          v1 = vertices[vi[1]]
          v2 = vertices[vi[2]]

          # Inline MVP transform for all 3 vertices (no Vec3 allocation)
          # Vertex 0
          clip0x = mvp[0] * v0x + mvp[1] * v0y + mvp[2] * v0z + mvp[3]
          clip0y = mvp[4] * v0x + mvp[5] * v0y + mvp[6] * v0z + mvp[7]
          clip0z = mvp[8] * v0x + mvp[9] * v0y + mvp[10] * v0z + mvp[11]
          w0 = mvp[12] * v0x + mvp[13] * v0y + mvp[14] * v0z + mvp[15]

          # Vertex 1
          v1x, v1y, v1z = v1[0], v1[1], v1[2]
          clip1x = mvp[0] * v1x + mvp[1] * v1y + mvp[2] * v1z + mvp[3]
          clip1y = mvp[4] * v1x + mvp[5] * v1y + mvp[6] * v1z + mvp[7]
          clip1z = mvp[8] * v1x + mvp[9] * v1y + mvp[10] * v1z + mvp[11]
          w1 = mvp[12] * v1x + mvp[13] * v1y + mvp[14] * v1z + mvp[15]

          # Vertex 2
          v2x, v2y, v2z = v2[0], v2[1], v2[2]
          clip2x = mvp[0] * v2x + mvp[1] * v2y + mvp[2] * v2z + mvp[3]
          clip2y = mvp[4] * v2x + mvp[5] * v2y + mvp[6] * v2z + mvp[7]
          clip2z = mvp[8] * v2x + mvp[9] * v2y + mvp[10] * v2z + mvp[11]
          w2 = mvp[12] * v2x + mvp[13] * v2y + mvp[14] * v2z + mvp[15]

          # Skip triangles entirely behind the near plane or beyond the fog
          next if w0 < near && w1 < near && w2 < near
          next if fog_far && w0 > fog_far && w1 > fog_far && w2 > fog_far

          uv = face[:texture] && face[:uv]
          r = face[:r]
          g = face[:g]
          b = face[:b]
          if lit || fogs
            r, g, b = shade(r, g, b, n[0], n[1], n[2], (w0 + w1 + w2) * 0.333333, lit, fogs)
          end

          # Triangles crossing the near plane are clipped instead of dropped
          if w0 < near || w1 < near || w2 < near
            ts = VOXEL_TEX_SIZE
            emit_clipped(triangles, [
              [clip0x, clip0y, clip0z, w0, uv ? uv[0][0] * ts : 0, uv ? uv[0][1] * ts : 0],
              [clip1x, clip1y, clip1z, w1, uv ? uv[1][0] * ts : 0, uv ? uv[1][1] * ts : 0],
              [clip2x, clip2y, clip2z, w2, uv ? uv[2][0] * ts : 0, uv ? uv[2][1] * ts : 0]
            ], near, r, g, b, face[:a], uv ? face[:texture] : nil, !uv)
            next
          end

          # Inline perspective divide (no Vec3 allocation)
          inv_w0 = 1.0 / w0
          inv_w1 = 1.0 / w1
          inv_w2 = 1.0 / w2

          ndc0x = clip0x * inv_w0
          ndc0y = clip0y * inv_w0
          ndc0z = clip0z * inv_w0
          ndc1x = clip1x * inv_w1
          ndc1y = clip1y * inv_w1
          ndc1z = clip1z * inv_w1
          ndc2x = clip2x * inv_w2
          ndc2y = clip2y * inv_w2
          ndc2z = clip2z * inv_w2

          # Inline frustum culling
          next if ndc0z > 1.0 && ndc1z > 1.0 && ndc2z > 1.0

          margin = NDC_MARGIN
          next if ndc0x < -margin && ndc1x < -margin && ndc2x < -margin
          next if ndc0x > margin && ndc1x > margin && ndc2x > margin
          next if ndc0y < -margin && ndc1y < -margin && ndc2y < -margin
          next if ndc0y > margin && ndc1y > margin && ndc2y > margin

          # Inline NDC to screen conversion
          screen0x = (ndc0x + 1.0) * HALF_WIDTH
          screen0y = (ndc0y + 1.0) * HALF_HEIGHT
          screen1x = (ndc1x + 1.0) * HALF_WIDTH
          screen1y = (ndc1y + 1.0) * HALF_HEIGHT
          screen2x = (ndc2x + 1.0) * HALF_WIDTH
          screen2y = (ndc2y + 1.0) * HALF_HEIGHT

          z_depth = (clip0z + clip1z + clip2z) * 0.333333

          # Textured faces map their UVs (normalized 0-1 -> texture pixels).
          # Solid colours are :solid sprites, which DragonRuby only draws as
          # triangles when source coordinates are set. One hash literal with
          # all keys: growing the hash key by key costs ~10% of the render.
          if uv
            ts = VOXEL_TEX_SIZE
            path = face[:texture]
            sx0 = uv[0][0] * ts
            sy0 = uv[0][1] * ts
            sx1 = uv[1][0] * ts
            sy1 = uv[1][1] * ts
            sx2 = uv[2][0] * ts
            sy2 = uv[2][1] * ts
          else
            path = :solid
            sx0 = 0
            sy0 = 0
            sx1 = 1
            sy1 = 0
            sx2 = 0
            sy2 = 1
          end

          triangles << {
            x: screen0x, y: screen0y,
            x2: screen1x, y2: screen1y,
            x3: screen2x, y3: screen2y,
            z_depth: z_depth,
            r: r, g: g, b: b, a: face[:a],
            path: path,
            source_x: sx0, source_y: sy0,
            source_x2: sx1, source_y2: sy1,
            source_x3: sx2, source_y3: sy2
          }
        end

        triangles.sort_by { |t| -t[:z_depth] }
      end

      # Project a world-space point to screen coordinates.
      # Returns [screen_x, screen_y] or nil if the point is behind the camera.
      def project_point(camera, x, y, z)
        vp = (camera.get_projection_matrix * camera.get_view_matrix).data

        clip_x = vp[0] * x + vp[1] * y + vp[2] * z + vp[3]
        clip_y = vp[4] * x + vp[5] * y + vp[6] * z + vp[7]
        w = vp[12] * x + vp[13] * y + vp[14] * z + vp[15]

        return nil if w <= 0.01

        inv_w = 1.0 / w
        [(clip_x * inv_w + 1.0) * HALF_WIDTH, (clip_y * inv_w + 1.0) * HALF_HEIGHT]
      end

      # Clips a triangle crossing the near plane (w = near) against it and
      # emits the resulting polygon as a triangle fan. Each poly entry is
      # [clip_x, clip_y, clip_z, w, u, v]; u/v are interpolated with it.
      def emit_clipped(triangles, poly, near, r, g, b, a, path, solid)
        out = []
        n = poly.size
        n.times do |i|
          p = poly[i]
          q = poly[(i + 1) % n]
          p_in = p[3] >= near
          q_in = q[3] >= near
          out << p if p_in
          next if p_in == q_in

          t = (near - p[3]) / (q[3] - p[3])
          out << [p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t,
                  p[2] + (q[2] - p[2]) * t, near,
                  p[4] + (q[4] - p[4]) * t, p[5] + (q[5] - p[5]) * t]
        end
        return if out.size < 3

        pts = out.map do |p|
          inv_w = 1.0 / p[3]
          [(p[0] * inv_w + 1.0) * HALF_WIDTH, (p[1] * inv_w + 1.0) * HALF_HEIGHT, p[2], p[4], p[5]]
        end

        a0 = pts[0]
        (1...pts.size - 1).each do |k|
          b1 = pts[k]
          c1 = pts[k + 1]
          triangle = {
            x: a0[0], y: a0[1],
            x2: b1[0], y2: b1[1],
            x3: c1[0], y3: c1[1],
            z_depth: (a0[2] + b1[2] + c1[2]) * 0.333333,
            r: r, g: g, b: b, a: a
          }
          if solid
            triangle[:path] = :solid
            triangle[:source_x] = 0
            triangle[:source_y] = 0
            triangle[:source_x2] = 1
            triangle[:source_y2] = 0
            triangle[:source_x3] = 0
            triangle[:source_y3] = 1
          end
          if path
            triangle[:path] = path
            triangle[:source_x] = a0[3]
            triangle[:source_y] = a0[4]
            triangle[:source_x2] = b1[3]
            triangle[:source_y2] = b1[4]
            triangle[:source_x3] = c1[3]
            triangle[:source_y3] = c1[4]
          end
          triangles << triangle
        end
      end

      private

      # [lx, ly, lz, ambient] with a normalized direction, or nil.
      def light_setup(light)
        return nil unless light

        dx, dy, dz = light[:direction] || [0.4, 1.0, 0.3]
        len = Math.sqrt(dx * dx + dy * dy + dz * dz)
        [dx / len, dy / len, dz / len, light[:ambient] || 0.35]
      end

      # [near, far, r, g, b, 1 / (far - near)], or nil.
      def fog_setup(fog)
        return nil unless fog

        near = fog[:near].to_f
        far = fog[:far].to_f
        color = fog[:color] || [0, 0, 0]
        [near, far, color[0], color[1], color[2], 1.0 / (far - near)]
      end

      # Applies flat lighting (unit world normal) and distance fog to a base
      # colour. Returns [r, g, b].
      def shade(r, g, b, nx, ny, nz, depth, lit, fogs)
        if lit
          d = nx * lit[0] + ny * lit[1] + nz * lit[2]
          k = lit[3] + (1.0 - lit[3]) * (d > 0 ? d : 0.0)
          r *= k
          g *= k
          b *= k
        end
        if fogs
          f = (depth - fogs[0]) * fogs[5]
          if f > 0
            f = 1.0 if f > 1.0
            r += (fogs[2] - r) * f
            g += (fogs[3] - g) * f
            b += (fogs[4] - b) * f
          end
        end
        [r, g, b]
      end

      # Inverse of the upper 3x3 of a row-major 4x4 matrix as 9 row-major
      # values, or nil if it is singular (e.g. a zero scale).
      def invert3(m)
        a = m[0]
        b = m[1]
        c = m[2]
        d = m[4]
        e = m[5]
        f = m[6]
        g = m[8]
        h = m[9]
        i = m[10]
        det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
        return nil if det.abs < 1e-12

        s = 1.0 / det
        [(e * i - f * h) * s, (c * h - b * i) * s, (b * f - c * e) * s,
         (f * g - d * i) * s, (a * i - c * g) * s, (c * d - a * f) * s,
         (d * h - e * g) * s, (b * g - a * h) * s, (a * e - b * d) * s]
      end

      def model_behind_camera?(model, cam_pos, cam_forward)
        # Vector from camera to model center
        dx = model.position.x - cam_pos.x
        dy = model.position.y - cam_pos.y
        dz = model.position.z - cam_pos.z

        # Dot product with camera forward
        dot = dx * cam_forward.x + dy * cam_forward.y + dz * cam_forward.z

        # If negative, model is behind camera (with margin for model size)
        dot < -5.0
      end

      def render_model_optimized(triangles, model, m, mvp, cam_pos, near, lit, fogs)
        mesh = model.mesh
        vertices = mesh.vertices
        faces = mesh.faces
        face_normals = mesh.face_normals
        uvs = mesh.uvs
        texture = model.texture
        color = model.color
        color_r = color[:r]
        color_g = color[:g]
        color_b = color[:b]
        color_a = color[:a]
        fog_far = fogs ? fogs[1] : nil

        # The inverse model matrix brings the camera into model space for back
        # face culling, and (transposed) face normals into world space.
        inv = invert3(m)
        return unless inv

        tx = cam_pos.x - m[3]
        ty = cam_pos.y - m[7]
        tz = cam_pos.z - m[11]
        cx = inv[0] * tx + inv[1] * ty + inv[2] * tz
        cy = inv[3] * tx + inv[4] * ty + inv[5] * tz
        cz = inv[6] * tx + inv[7] * ty + inv[8] * tz

        # Transform every vertex to clip space once; faces share vertices
        # (up to 6 per sphere vertex), so per-corner transforms repeat work.
        # The arrays are reused across models and frames.
        xs = (@clip_x ||= [])
        ys = (@clip_y ||= [])
        zs = (@clip_z ||= [])
        ws = (@clip_w ||= [])
        m0 = mvp[0]
        m1 = mvp[1]
        m2 = mvp[2]
        m3 = mvp[3]
        m4 = mvp[4]
        m5 = mvp[5]
        m6 = mvp[6]
        m7 = mvp[7]
        m8 = mvp[8]
        m9 = mvp[9]
        m10 = mvp[10]
        m11 = mvp[11]
        m12 = mvp[12]
        m13 = mvp[13]
        m14 = mvp[14]
        m15 = mvp[15]
        vertices.each_with_index do |v, i|
          x = v.x
          y = v.y
          z = v.z
          xs[i] = m0 * x + m1 * y + m2 * z + m3
          ys[i] = m4 * x + m5 * y + m6 * z + m7
          zs[i] = m8 * x + m9 * y + m10 * z + m11
          ws[i] = m12 * x + m13 * y + m14 * z + m15
        end

        faces.each_with_index do |face, fi|
          vi = face[:v]
          v0 = vertices[vi[0]]
          v0x, v0y, v0z = v0.x, v0.y, v0.z

          # Back face culling in model space, before any projection work
          fn = face_normals[fi]
          nx = fn[0]
          ny = fn[1]
          nz = fn[2]
          next if (cx - v0x) * nx + (cy - v0y) * ny + (cz - v0z) * nz <= 0

          i0 = vi[0]
          i1 = vi[1]
          i2 = vi[2]
          clip0x = xs[i0]
          clip0y = ys[i0]
          clip0z = zs[i0]
          w0 = ws[i0]
          clip1x = xs[i1]
          clip1y = ys[i1]
          clip1z = zs[i1]
          w1 = ws[i1]
          clip2x = xs[i2]
          clip2y = ys[i2]
          clip2z = zs[i2]
          w2 = ws[i2]

          # Skip triangles entirely behind the near plane or beyond the fog
          next if w0 < near && w1 < near && w2 < near
          next if fog_far && w0 > fog_far && w1 > fog_far && w2 > fog_far

          uv0 = uv1 = uv2 = nil
          if texture && face[:uv] && uvs.length > 0
            uv_indices = face[:uv]
            uv0_idx = uv_indices[0]
            uv1_idx = uv_indices[1]
            uv2_idx = uv_indices[2]

            if uv0_idx && uv0_idx >= 0 && uv0_idx < uvs.length &&
               uv1_idx && uv1_idx >= 0 && uv1_idx < uvs.length &&
               uv2_idx && uv2_idx >= 0 && uv2_idx < uvs.length
              uv0 = uvs[uv0_idx]
              uv1 = uvs[uv1_idx]
              uv2 = uvs[uv2_idx]
            end
          end

          r = color_r
          g = color_g
          b = color_b
          if lit || fogs
            # World normal = inverse transpose of the model matrix * normal
            wx = inv[0] * nx + inv[3] * ny + inv[6] * nz
            wy = inv[1] * nx + inv[4] * ny + inv[7] * nz
            wz = inv[2] * nx + inv[5] * ny + inv[8] * nz
            wl = Math.sqrt(wx * wx + wy * wy + wz * wz)
            wl = 1.0 if wl == 0
            r, g, b = shade(r, g, b, wx / wl, wy / wl, wz / wl, (w0 + w1 + w2) * 0.333333, lit, fogs)
          end

          # Triangles crossing the near plane are clipped instead of dropped
          if w0 < near || w1 < near || w2 < near
            emit_clipped(triangles, [
              [clip0x, clip0y, clip0z, w0, uv0 ? uv0[0] : 0, uv0 ? uv0[1] : 0],
              [clip1x, clip1y, clip1z, w1, uv1 ? uv1[0] : 0, uv1 ? uv1[1] : 0],
              [clip2x, clip2y, clip2z, w2, uv2 ? uv2[0] : 0, uv2 ? uv2[1] : 0]
            ], near, r, g, b, color_a, uv0 ? texture : nil, !uv0)
            next
          end

          # Inline perspective divide
          inv_w0 = 1.0 / w0
          inv_w1 = 1.0 / w1
          inv_w2 = 1.0 / w2

          ndc0x = clip0x * inv_w0
          ndc0y = clip0y * inv_w0
          ndc0z = clip0z * inv_w0
          ndc1x = clip1x * inv_w1
          ndc1y = clip1y * inv_w1
          ndc1z = clip1z * inv_w1
          ndc2x = clip2x * inv_w2
          ndc2y = clip2y * inv_w2
          ndc2z = clip2z * inv_w2

          # Inline frustum culling
          next if ndc0z > 1.0 && ndc1z > 1.0 && ndc2z > 1.0

          margin = NDC_MARGIN
          next if ndc0x < -margin && ndc1x < -margin && ndc2x < -margin
          next if ndc0x > margin && ndc1x > margin && ndc2x > margin
          next if ndc0y < -margin && ndc1y < -margin && ndc2y < -margin
          next if ndc0y > margin && ndc1y > margin && ndc2y > margin

          # Inline NDC to screen conversion
          screen0x = (ndc0x + 1.0) * HALF_WIDTH
          screen0y = (ndc0y + 1.0) * HALF_HEIGHT
          screen1x = (ndc1x + 1.0) * HALF_WIDTH
          screen1y = (ndc1y + 1.0) * HALF_HEIGHT
          screen2x = (ndc2x + 1.0) * HALF_WIDTH
          screen2y = (ndc2y + 1.0) * HALF_HEIGHT

          z_depth = (clip0z + clip1z + clip2z) * 0.333333

          # Solid colours are :solid sprites with source coordinates (see
          # render_voxel_world); one hash literal with all keys.
          if uv0
            path = texture
            sx0 = uv0[0]
            sy0 = uv0[1]
            sx1 = uv1[0]
            sy1 = uv1[1]
            sx2 = uv2[0]
            sy2 = uv2[1]
          else
            path = :solid
            sx0 = 0
            sy0 = 0
            sx1 = 1
            sy1 = 0
            sx2 = 0
            sy2 = 1
          end

          triangles << {
            x: screen0x, y: screen0y,
            x2: screen1x, y2: screen1y,
            x3: screen2x, y3: screen2y,
            z_depth: z_depth,
            r: r, g: g, b: b, a: color_a,
            path: path,
            source_x: sx0, source_y: sy0,
            source_x2: sx1, source_y2: sy1,
            source_x3: sx2, source_y3: sy2
          }
        end
      end
    end
  end
end
