module D3D
  module Collisions
    EPSILON = 1e-6

    class << self
      def ray_triangle(ray_origin, ray_direction, v0, v1, v2)
        edge1 = v1 - v0
        edge2 = v2 - v0
        h = ray_direction.cross(edge2)
        a = edge1.dot(h)

        return nil if a.abs < EPSILON

        f = 1.0 / a
        s = ray_origin - v0
        u = f * s.dot(h)

        return nil if u < 0.0 || u > 1.0

        q = s.cross(edge1)
        v = f * ray_direction.dot(q)

        return nil if v < 0.0 || u + v > 1.0

        t = f * edge2.dot(q)

        return nil if t < EPSILON

        hit_point = ray_origin + ray_direction * t
        { t: t, point: hit_point, u: u, v: v }
      end

      def ray_model(ray_origin, ray_direction, model)
        return nil unless model.visible

        closest_hit = nil
        mesh = model.mesh
        model_matrix = model.get_model_matrix

        mesh.faces.each_with_index do |face, face_idx|
          v0 = model_matrix.transform_point(mesh.vertices[face[:v][0]])
          v1 = model_matrix.transform_point(mesh.vertices[face[:v][1]])
          v2 = model_matrix.transform_point(mesh.vertices[face[:v][2]])

          hit = ray_triangle(ray_origin, ray_direction, v0, v1, v2)
          next unless hit

          if closest_hit.nil? || hit[:t] < closest_hit[:t]
            closest_hit = hit.merge(
              model: model,
              face_index: face_idx,
              v0: v0, v1: v1, v2: v2
            )
          end
        end

        closest_hit
      end

      def ray_models(ray_origin, ray_direction, models)
        closest_hit = nil

        models.each do |model|
          hit = ray_model(ray_origin, ray_direction, model)
          next unless hit

          if closest_hit.nil? || hit[:t] < closest_hit[:t]
            closest_hit = hit
          end
        end

        closest_hit
      end

      def sphere_model(sphere_center, sphere_radius, model)
        return nil unless model.visible

        mesh = model.mesh
        model_matrix = model.get_model_matrix

        mesh.faces.each do |face|
          v0 = model_matrix.transform_point(mesh.vertices[face[:v][0]])
          v1 = model_matrix.transform_point(mesh.vertices[face[:v][1]])
          v2 = model_matrix.transform_point(mesh.vertices[face[:v][2]])

          closest_point = closest_point_on_triangle(sphere_center, v0, v1, v2)
          distance = sphere_center.distance_to(closest_point)

          if distance <= sphere_radius
            normal = (sphere_center - closest_point).normalize
            penetration = sphere_radius - distance
            return {
              point: closest_point,
              normal: normal,
              penetration: penetration,
              model: model
            }
          end
        end

        nil
      end

      def sphere_models(sphere_center, sphere_radius, models)
        collisions = []

        models.each do |model|
          collision = sphere_model(sphere_center, sphere_radius, model)
          collisions << collision if collision
        end

        collisions
      end

      def point_in_triangle(point, v0, v1, v2)
        edge0 = v1 - v0
        edge1 = v2 - v0
        edge2 = point - v0

        dot00 = edge0.dot(edge0)
        dot01 = edge0.dot(edge1)
        dot02 = edge0.dot(edge2)
        dot11 = edge1.dot(edge1)
        dot12 = edge1.dot(edge2)

        inv_denom = 1.0 / (dot00 * dot11 - dot01 * dot01)
        u = (dot11 * dot02 - dot01 * dot12) * inv_denom
        v = (dot00 * dot12 - dot01 * dot02) * inv_denom

        u >= 0 && v >= 0 && u + v <= 1
      end

      def aabb_intersects?(min1, max1, min2, max2)
        min1.x <= max2.x && max1.x >= min2.x &&
        min1.y <= max2.y && max1.y >= min2.y &&
        min1.z <= max2.z && max1.z >= min2.z
      end

      def sphere_intersects_sphere?(center1, radius1, center2, radius2)
        distance = center1.distance_to(center2)
        distance <= radius1 + radius2
      end

      private

      def closest_point_on_triangle(point, v0, v1, v2)
        edge0 = v1 - v0
        edge1 = v2 - v0
        v0_to_point = point - v0

        d00 = edge0.dot(edge0)
        d01 = edge0.dot(edge1)
        d11 = edge1.dot(edge1)
        d20 = v0_to_point.dot(edge0)
        d21 = v0_to_point.dot(edge1)

        denom = d00 * d11 - d01 * d01
        v = (d11 * d20 - d01 * d21) / denom
        w = (d00 * d21 - d01 * d20) / denom
        u = 1.0 - v - w

        if u >= 0 && v >= 0 && w >= 0
          return v0 + edge0 * v + edge1 * w
        end

        if u < 0
          return closest_point_on_segment(point, v1, v2)
        elsif v < 0
          return closest_point_on_segment(point, v0, v2)
        else
          return closest_point_on_segment(point, v0, v1)
        end
      end

      def closest_point_on_segment(point, a, b)
        ab = b - a
        t = (point - a).dot(ab) / ab.dot(ab)
        t = [[t, 0].max, 1].min
        a + ab * t
      end
    end
  end
end
