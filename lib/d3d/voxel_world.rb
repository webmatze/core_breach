module D3D
  class VoxelWorld
    attr_reader :blocks, :mesh_data

    # Face definitions: [vertex offsets for 2 triangles, normal direction check offset, UV coordinates]
    # Each face has 6 vertices (2 triangles) defined as offsets from block position
    # UV coordinates are normalized 0-1 range
    FACES = {
      # Top face (+Y) - check if block above is empty
      top: {
        check: [0, 1, 0],
        vertices: [
          # Triangle 1
          [0, 1, 0], [1, 1, 0], [1, 1, 1],
          # Triangle 2
          [0, 1, 0], [1, 1, 1], [0, 1, 1]
        ],
        uvs: [
          # Triangle 1: bottom-left, bottom-right, top-right
          [0, 0], [1, 0], [1, 1],
          # Triangle 2: bottom-left, top-right, top-left
          [0, 0], [1, 1], [0, 1]
        ]
      },
      # Bottom face (-Y) - check if block below is empty
      bottom: {
        check: [0, -1, 0],
        vertices: [
          [0, 0, 1], [1, 0, 1], [1, 0, 0],
          [0, 0, 1], [1, 0, 0], [0, 0, 0]
        ],
        uvs: [
          [0, 1], [1, 1], [1, 0],
          [0, 1], [1, 0], [0, 0]
        ]
      },
      # Front face (+Z) - check if block in front is empty
      front: {
        check: [0, 0, 1],
        vertices: [
          [0, 0, 1], [0, 1, 1], [1, 1, 1],
          [0, 0, 1], [1, 1, 1], [1, 0, 1]
        ],
        uvs: [
          [0, 0], [0, 1], [1, 1],
          [0, 0], [1, 1], [1, 0]
        ]
      },
      # Back face (-Z) - check if block behind is empty
      back: {
        check: [0, 0, -1],
        vertices: [
          [1, 0, 0], [1, 1, 0], [0, 1, 0],
          [1, 0, 0], [0, 1, 0], [0, 0, 0]
        ],
        uvs: [
          [0, 0], [0, 1], [1, 1],
          [0, 0], [1, 1], [1, 0]
        ]
      },
      # Right face (+X) - check if block to right is empty
      right: {
        check: [1, 0, 0],
        vertices: [
          [1, 0, 1], [1, 1, 1], [1, 1, 0],
          [1, 0, 1], [1, 1, 0], [1, 0, 0]
        ],
        uvs: [
          [0, 0], [0, 1], [1, 1],
          [0, 0], [1, 1], [1, 0]
        ]
      },
      # Left face (-X) - check if block to left is empty
      left: {
        check: [-1, 0, 0],
        vertices: [
          [0, 0, 0], [0, 1, 0], [0, 1, 1],
          [0, 0, 0], [0, 1, 1], [0, 0, 1]
        ],
        uvs: [
          [0, 0], [0, 1], [1, 1],
          [0, 0], [1, 1], [1, 0]
        ]
      }
    }.freeze

    def initialize
      @blocks = {}  # Spatial hash: "x,y,z" => color_hash
      @mesh_data = nil
      @dirty = true
    end

    def add_block(x, y, z, color, texture: nil)
      key = "#{x.to_i},#{y.to_i},#{z.to_i}"
      @blocks[key] = {
        x: x.to_i,
        y: y.to_i,
        z: z.to_i,
        r: color[:r],
        g: color[:g],
        b: color[:b],
        a: color[:a] || 255,
        texture: texture
      }
      @dirty = true
    end

    def remove_block(x, y, z)
      key = "#{x.to_i},#{y.to_i},#{z.to_i}"
      @blocks.delete(key)
      @dirty = true
    end

    def has_block?(x, y, z)
      @blocks.key?("#{x.to_i},#{y.to_i},#{z.to_i}")
    end

    def get_block(x, y, z)
      @blocks["#{x.to_i},#{y.to_i},#{z.to_i}"]
    end

    def block_count
      @blocks.size
    end

    def build_mesh
      return @mesh_data unless @dirty

      # Build arrays of vertices and faces for exposed faces only
      vertices = []
      faces = []

      @blocks.each_value do |block|
        bx, by, bz = block[:x], block[:y], block[:z]
        r, g, b, a = block[:r], block[:g], block[:b], block[:a]
        texture = block[:texture]

        FACES.each do |_face_name, face_data|
          check = face_data[:check]
          neighbor_x = bx + check[0]
          neighbor_y = by + check[1]
          neighbor_z = bz + check[2]

          # Only add face if no neighbor block exists
          next if has_block?(neighbor_x, neighbor_y, neighbor_z)

          verts = face_data[:vertices]
          uvs = face_data[:uvs]
          base_idx = vertices.size

          # Add 6 vertices for this face (2 triangles)
          verts.each do |v_offset|
            vertices << [
              bx + v_offset[0],
              by + v_offset[1],
              bz + v_offset[2]
            ]
          end

          # Add 2 triangle faces with color, texture, and UVs
          faces << {
            v: [base_idx, base_idx + 1, base_idx + 2],
            uv: [uvs[0], uvs[1], uvs[2]],
            n: check,
            texture: texture,
            r: r, g: g, b: b, a: a
          }
          faces << {
            v: [base_idx + 3, base_idx + 4, base_idx + 5],
            uv: [uvs[3], uvs[4], uvs[5]],
            n: check,
            texture: texture,
            r: r, g: g, b: b, a: a
          }
        end
      end

      @mesh_data = { vertices: vertices, faces: faces }
      @dirty = false
      @mesh_data
    end

    def rebuild!
      @dirty = true
      build_mesh
    end

    # The four corners of a block face, given a raycast hit
    # ({ x:, y:, z:, normal: [nx, ny, nz] }). Corners are returned in edge-loop
    # order as [x, y, z] arrays, pushed `lift` outward along the normal to
    # avoid z-fighting. Returns nil for a zero normal.
    def self.face_corners(hit, lift: 0.004)
      nx, ny, nz = hit[:normal]
      return nil if nx == 0 && ny == 0 && nz == 0

      face_offset = ->(n, base) { n > 0 ? base + 1 + lift : base - lift }

      if nx != 0
        fx = face_offset.call(nx, hit[:x])
        [[fx, hit[:y], hit[:z]], [fx, hit[:y] + 1, hit[:z]],
         [fx, hit[:y] + 1, hit[:z] + 1], [fx, hit[:y], hit[:z] + 1]]
      elsif ny != 0
        fy = face_offset.call(ny, hit[:y])
        [[hit[:x], fy, hit[:z]], [hit[:x] + 1, fy, hit[:z]],
         [hit[:x] + 1, fy, hit[:z] + 1], [hit[:x], fy, hit[:z] + 1]]
      else
        fz = face_offset.call(nz, hit[:z])
        [[hit[:x], hit[:y], fz], [hit[:x] + 1, hit[:y], fz],
         [hit[:x] + 1, hit[:y] + 1, fz], [hit[:x], hit[:y] + 1, fz]]
      end
    end

    # True if the AABB (min/max as Vec3) overlaps any block. Boxes that only
    # touch a block face (e.g. standing exactly on top) do not intersect.
    def aabb_intersects?(min, max)
      eps = 1e-9
      min_x = min.x.floor
      max_x = (max.x - eps).floor
      min_y = min.y.floor
      max_y = (max.y - eps).floor
      min_z = min.z.floor
      max_z = (max.z - eps).floor

      (min_x..max_x).each do |bx|
        (min_y..max_y).each do |by|
          (min_z..max_z).each do |bz|
            return true if has_block?(bx, by, bz)
          end
        end
      end
      false
    end

    # Voxel raycast (Amanatides & Woo DDA). Returns the first solid block hit
    # as { x:, y:, z:, normal: [nx, ny, nz], distance: } or nil.
    def raycast(origin, dir, max_distance)
      x = origin.x.floor
      y = origin.y.floor
      z = origin.z.floor

      step_x = dir.x > 0 ? 1 : -1
      step_y = dir.y > 0 ? 1 : -1
      step_z = dir.z > 0 ? 1 : -1

      inf = Float::INFINITY
      t_delta_x = dir.x == 0 ? inf : (1.0 / dir.x).abs
      t_delta_y = dir.y == 0 ? inf : (1.0 / dir.y).abs
      t_delta_z = dir.z == 0 ? inf : (1.0 / dir.z).abs

      t_max_x = dir.x == 0 ? inf : ((dir.x > 0 ? x + 1 - origin.x : origin.x - x) * t_delta_x)
      t_max_y = dir.y == 0 ? inf : ((dir.y > 0 ? y + 1 - origin.y : origin.y - y) * t_delta_y)
      t_max_z = dir.z == 0 ? inf : ((dir.z > 0 ? z + 1 - origin.z : origin.z - z) * t_delta_z)

      normal = [0, 0, 0]
      t = 0.0

      while t <= max_distance
        if has_block?(x, y, z)
          return { x: x, y: y, z: z, normal: normal, distance: t }
        end

        if t_max_x < t_max_y && t_max_x < t_max_z
          x += step_x
          t = t_max_x
          t_max_x += t_delta_x
          normal = [-step_x, 0, 0]
        elsif t_max_y < t_max_z
          y += step_y
          t = t_max_y
          t_max_y += t_delta_y
          normal = [0, -step_y, 0]
        else
          z += step_z
          t = t_max_z
          t_max_z += t_delta_z
          normal = [0, 0, -step_z]
        end
      end

      nil
    end
  end
end
