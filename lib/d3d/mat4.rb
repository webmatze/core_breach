module D3D
  class Mat4
    attr_accessor :data

    def initialize(data = nil)
      @data = data || identity_data
    end

    def [](row, col)
      @data[row * 4 + col]
    end

    def []=(row, col, value)
      @data[row * 4 + col] = value
    end

    def dup
      Mat4.new(@data.dup)
    end

    def *(other)
      if other.is_a?(Mat4)
        multiply_matrix(other)
      elsif other.is_a?(Vec3)
        multiply_vec3(other)
      else
        raise ArgumentError, "Cannot multiply Mat4 with #{other.class}"
      end
    end

    def multiply_matrix(other)
      result = Mat4.new(Array.new(16, 0.0))
      4.times do |row|
        4.times do |col|
          sum = 0.0
          4.times do |k|
            sum += self[row, k] * other[k, col]
          end
          result[row, col] = sum
        end
      end
      result
    end

    def multiply_vec3(vec, w = 1.0)
      x = self[0, 0] * vec.x + self[0, 1] * vec.y + self[0, 2] * vec.z + self[0, 3] * w
      y = self[1, 0] * vec.x + self[1, 1] * vec.y + self[1, 2] * vec.z + self[1, 3] * w
      z = self[2, 0] * vec.x + self[2, 1] * vec.y + self[2, 2] * vec.z + self[2, 3] * w
      w_out = self[3, 0] * vec.x + self[3, 1] * vec.y + self[3, 2] * vec.z + self[3, 3] * w
      [Vec3.new(x, y, z), w_out]
    end

    def transform_point(vec)
      result, w = multiply_vec3(vec, 1.0)
      if w != 0 && w != 1
        result.x /= w
        result.y /= w
        result.z /= w
      end
      result
    end

    def transform_direction(vec)
      result, _ = multiply_vec3(vec, 0.0)
      result
    end

    def to_s
      rows = 4.times.map do |row|
        4.times.map { |col| format("%8.4f", self[row, col]) }.join(" ")
      end
      "Mat4[\n  #{rows.join("\n  ")}\n]"
    end

    def inspect
      to_s
    end

    # Class methods for creating common matrices
    def self.identity
      Mat4.new
    end

    def self.translation(x, y, z)
      mat = Mat4.new
      mat[0, 3] = x.to_f
      mat[1, 3] = y.to_f
      mat[2, 3] = z.to_f
      mat
    end

    def self.translation_vec(vec)
      translation(vec.x, vec.y, vec.z)
    end

    def self.scale(x, y = nil, z = nil)
      y ||= x
      z ||= x
      mat = Mat4.new
      mat[0, 0] = x.to_f
      mat[1, 1] = y.to_f
      mat[2, 2] = z.to_f
      mat
    end

    def self.scale_vec(vec)
      scale(vec.x, vec.y, vec.z)
    end

    def self.rotation_x(angle)
      c = Math.cos(angle)
      s = Math.sin(angle)
      mat = Mat4.new
      mat[1, 1] = c
      mat[1, 2] = -s
      mat[2, 1] = s
      mat[2, 2] = c
      mat
    end

    def self.rotation_y(angle)
      c = Math.cos(angle)
      s = Math.sin(angle)
      mat = Mat4.new
      mat[0, 0] = c
      mat[0, 2] = s
      mat[2, 0] = -s
      mat[2, 2] = c
      mat
    end

    def self.rotation_z(angle)
      c = Math.cos(angle)
      s = Math.sin(angle)
      mat = Mat4.new
      mat[0, 0] = c
      mat[0, 1] = -s
      mat[1, 0] = s
      mat[1, 1] = c
      mat
    end

    def self.rotation(rx, ry, rz)
      rotation_z(rz) * rotation_y(ry) * rotation_x(rx)
    end

    def self.rotation_vec(vec)
      rotation(vec.x, vec.y, vec.z)
    end

    def self.perspective(fov_degrees, aspect, near, far)
      fov_rad = fov_degrees * Math::PI / 180.0
      tan_half_fov = Math.tan(fov_rad / 2.0)

      mat = Mat4.new(Array.new(16, 0.0))
      mat[0, 0] = 1.0 / (aspect * tan_half_fov)
      mat[1, 1] = 1.0 / tan_half_fov
      mat[2, 2] = -(far + near) / (far - near)
      mat[2, 3] = -(2.0 * far * near) / (far - near)
      mat[3, 2] = -1.0
      mat
    end

    def self.look_at(eye, target, up)
      forward = (eye - target).normalize
      right = up.cross(forward).normalize
      new_up = forward.cross(right)

      mat = Mat4.new
      mat[0, 0] = right.x
      mat[0, 1] = right.y
      mat[0, 2] = right.z
      mat[0, 3] = -right.dot(eye)

      mat[1, 0] = new_up.x
      mat[1, 1] = new_up.y
      mat[1, 2] = new_up.z
      mat[1, 3] = -new_up.dot(eye)

      mat[2, 0] = forward.x
      mat[2, 1] = forward.y
      mat[2, 2] = forward.z
      mat[2, 3] = -forward.dot(eye)

      mat
    end

    def self.orthographic(left, right, bottom, top, near, far)
      mat = Mat4.new(Array.new(16, 0.0))
      mat[0, 0] = 2.0 / (right - left)
      mat[1, 1] = 2.0 / (top - bottom)
      mat[2, 2] = -2.0 / (far - near)
      mat[0, 3] = -(right + left) / (right - left)
      mat[1, 3] = -(top + bottom) / (top - bottom)
      mat[2, 3] = -(far + near) / (far - near)
      mat[3, 3] = 1.0
      mat
    end

    private

    def identity_data
      [
        1.0, 0.0, 0.0, 0.0,
        0.0, 1.0, 0.0, 0.0,
        0.0, 0.0, 1.0, 0.0,
        0.0, 0.0, 0.0, 1.0
      ]
    end
  end
end
