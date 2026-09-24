# Small 3D vector helpers. Vectors are plain [x, y, z] arrays.
module V
  def self.add(a, b)
    [a[0] + b[0], a[1] + b[1], a[2] + b[2]]
  end

  def self.sub(a, b)
    [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
  end

  def self.scale(a, s)
    [a[0] * s, a[1] * s, a[2] * s]
  end

  # a + b * s
  def self.madd(a, b, s)
    [a[0] + b[0] * s, a[1] + b[1] * s, a[2] + b[2] * s]
  end

  def self.dot(a, b)
    a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
  end

  def self.cross(a, b)
    [a[1] * b[2] - a[2] * b[1],
     a[2] * b[0] - a[0] * b[2],
     a[0] * b[1] - a[1] * b[0]]
  end

  def self.len(a)
    Math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])
  end

  def self.dist(a, b)
    dx = a[0] - b[0]
    dy = a[1] - b[1]
    dz = a[2] - b[2]
    Math.sqrt(dx * dx + dy * dy + dz * dz)
  end

  def self.dist2(a, b)
    dx = a[0] - b[0]
    dy = a[1] - b[1]
    dz = a[2] - b[2]
    dx * dx + dy * dy + dz * dz
  end

  def self.norm(a)
    l = len(a)
    return [0.0, 0.0, 1.0] if l < 1e-9
    [a[0] / l, a[1] / l, a[2] / l]
  end

  def self.lerp(a, b, t)
    [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t]
  end

  # Rotates the orthogonal pair (a, b) by ang radians so that a turns towards b.
  def self.rotate_pair(a, b, ang)
    c = Math.cos(ang)
    s = Math.sin(ang)
    [[a[0] * c + b[0] * s, a[1] * c + b[1] * s, a[2] * c + b[2] * s],
     [b[0] * c - a[0] * s, b[1] * c - a[1] * s, b[2] * c - a[2] * s]]
  end

  # Builds a right/up basis for a forward vector, keeping "up" close to world up.
  def self.basis_from_forward(fwd, up_hint = [0.0, 1.0, 0.0])
    right = cross(up_hint, fwd)
    right = cross([0.0, 0.0, 1.0], fwd) if len(right) < 1e-4
    right = norm(right)
    [right, cross(fwd, right)]
  end

  def self.random_unit(rng = nil)
    loop do
      v = [rand * 2 - 1, rand * 2 - 1, rand * 2 - 1]
      l = len(v)
      return scale(v, 1.0 / l) if l > 0.05 && l <= 1.0
    end
  end
end

def clamp(v, lo, hi)
  v < lo ? lo : (v > hi ? hi : v)
end

# Deterministic pseudo random numbers for level generation.
class Lcg
  def initialize(seed)
    @s = seed
  end

  def next_f
    @s = (@s * 1103515245 + 12345) % 2147483648
    @s / 2147483648.0
  end

  def int(lo, hi)
    lo + (next_f * (hi - lo + 1)).to_i
  end
end
