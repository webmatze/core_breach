# Low poly models for robots, the reactor and pickups. All designs are original.
# Local space: +x right, +y up, +z forward.
class Tri
  attr_reader :a, :b, :c, :color, :normal, :double_sided, :emissive

  def initialize(a, b, c, color, normal, double_sided, emissive)
    @a = a
    @b = b
    @c = c
    @color = color
    @normal = normal
    @double_sided = double_sided
    @emissive = emissive
  end
end

class Mesh
  attr_reader :verts, :tris, :radius

  def initialize
    @verts = []
    @tris = []
    @radius = 0.0
  end

  def vert(x, y, z)
    @verts << [x.to_f, y.to_f, z.to_f]
    l = Math.sqrt(x * x + y * y + z * z)
    @radius = l if l > @radius
    @verts.size - 1
  end

  # Adds a triangle whose winding is fixed so that its normal points away from
  # `inside` (the centre of the convex part it belongs to).
  def tri(a, b, c, color, inside: [0, 0, 0], double_sided: false, emissive: false)
    pa = @verts[a]
    n = V.norm(V.cross(V.sub(@verts[b], pa), V.sub(@verts[c], pa)))
    centroid = V.scale(V.add(V.add(pa, @verts[b]), @verts[c]), 1.0 / 3)
    if V.dot(n, V.sub(centroid, inside)) < 0
      b, c = c, b
      n = V.scale(n, -1)
    end
    @tris << Tri.new(a, b, c, color, n, double_sided, emissive)
  end

  def quad(a, b, c, d, color, **opts)
    tri(a, b, c, color, **opts)
    tri(a, c, d, color, **opts)
  end

  # Axis aligned box centred on (cx, cy, cz).
  def box(cx, cy, cz, sx, sy, sz, color, side_color = nil, **opts)
    side_color ||= color
    v = []
    [-1, 1].each do |z|
      [-1, 1].each do |y|
        [-1, 1].each do |x|
          v << vert(cx + x * sx, cy + y * sy, cz + z * sz)
        end
      end
    end
    inside = [cx, cy, cz]
    quad(v[0], v[1], v[3], v[2], side_color, inside: inside, **opts) # back
    quad(v[4], v[5], v[7], v[6], color, inside: inside, **opts)      # front
    quad(v[0], v[1], v[5], v[4], side_color, inside: inside, **opts) # bottom
    quad(v[2], v[3], v[7], v[6], side_color, inside: inside, **opts) # top
    quad(v[0], v[2], v[6], v[4], side_color, inside: inside, **opts) # left
    quad(v[1], v[3], v[7], v[5], side_color, inside: inside, **opts) # right
  end

  # Double cone around the z axis: `sides` ring vertices of radius r at z = 0,
  # tips at z = front and z = -back.
  def bipyramid(sides, r, front, back, colors, center: [0, 0, 0], axis: :z, **opts)
    ring = sides.times.map do |n|
      a = Math::PI * 2 * n / sides
      x = Math.cos(a) * r
      y = Math.sin(a) * r
      case axis
      when :z then vert(center[0] + x, center[1] + y, center[2])
      else         vert(center[0] + x, center[1], center[2] + y)
      end
    end
    tip_f = axis == :z ? vert(center[0], center[1], center[2] + front) : vert(center[0], center[1] + front, center[2])
    tip_b = axis == :z ? vert(center[0], center[1], center[2] - back) : vert(center[0], center[1] - back, center[2])
    sides.times do |n|
      m = (n + 1) % sides
      col = colors[n % colors.size]
      tri(ring[n], ring[m], tip_f, col, inside: center, **opts)
      tri(ring[n], ring[m], tip_b, col.map { |c| c * 0.7 }, inside: center, **opts)
    end
  end

  # ------------------------------------------------------------- models

  # Hovering sentry: diamond body, two swept fins and a glowing sensor.
  def self.drone
    m = new
    m.bipyramid 6, 1.5, 2.2, 1.6, [[200, 170, 60], [140, 120, 50]]
    fin = [[90, 90, 100]]
    [-1, 1].each do |s|
      a = m.vert(1.2 * s, 0, 0.8)
      b = m.vert(3.2 * s, 0.9, -1.4)
      c = m.vert(1.2 * s, 0, -1.0)
      m.tri a, b, c, fin[0], double_sided: true
      d = m.vert(3.2 * s, -0.9, -1.4)
      m.tri a, d, c, [70, 70, 80], double_sided: true
    end
    m.box 0, 0, 1.9, 0.45, 0.45, 0.2, [255, 60, 40], emissive: true
    m
  end

  # Fast rammer: long spike forward, three blades.
  def self.hunter
    m = new
    tip = m.vert(0, 0, 3.2)
    tail = m.vert(0, 0, -1.2)
    ring = 3.times.map do |n|
      a = Math::PI * 2 * n / 3 + Math::PI / 2
      m.vert(Math.cos(a) * 1.6, Math.sin(a) * 1.6, -0.4)
    end
    colors = [[60, 200, 90], [40, 150, 70], [80, 230, 120]]
    3.times do |n|
      k = (n + 1) % 3
      m.tri ring[n], ring[k], tip, colors[n]
      m.tri ring[n], ring[k], tail, [30, 90, 40]
    end
    3.times do |n|
      a = Math::PI * 2 * n / 3 - Math::PI / 2
      base1 = m.vert(Math.cos(a) * 0.5, Math.sin(a) * 0.5, 0.6)
      base2 = m.vert(Math.cos(a) * 0.5, Math.sin(a) * 0.5, -0.8)
      out = m.vert(Math.cos(a) * 2.6, Math.sin(a) * 2.6, -1.3)
      m.tri base1, base2, out, [190, 220, 190], double_sided: true
    end
    m
  end

  # Heavy gunship: armoured block with twin cannons.
  def self.brute
    m = new
    m.box 0, 0, 0, 2.2, 1.6, 2.0, [150, 80, 190], [100, 50, 130]
    m.box 0, 1.9, -0.4, 1.2, 0.35, 1.2, [120, 70, 150]
    [-1, 1].each do |s|
      m.box 2.8 * s, -0.3, 0.8, 0.5, 0.5, 2.0, [90, 90, 100], [60, 60, 70]
      m.box 2.8 * s, -0.3, 2.9, 0.3, 0.3, 0.1, [255, 120, 40], emissive: true
    end
    m.box 0, 0.3, 2.05, 1.2, 0.35, 0.1, [255, 60, 200], emissive: true
    m
  end

  def self.reactor_core
    m = new
    m.bipyramid 8, 4.0, 5.0, 5.0, [[255, 150, 40], [255, 90, 20]], axis: :y, emissive: true
    m
  end

  def self.reactor_frame
    m = new
    4.times do |n|
      a = Math::PI / 2 * n + Math::PI / 4
      x = Math.cos(a) * 7.5
      z = Math.sin(a) * 7.5
      m.box x, 0, z, 0.8, 8.0, 0.8, [120, 125, 140], [80, 85, 100]
    end
    m.box 0, -6.5, 0, 6.5, 0.6, 6.5, [100, 105, 120], [70, 75, 90]
    m.box 0, 6.5, 0, 6.5, 0.6, 6.5, [100, 105, 120], [70, 75, 90]
    m
  end

  def self.pickup(color)
    m = new
    dark = color.map { |c| c * 0.6 }
    m.bipyramid 4, 1.0, 1.3, 1.3, [color, dark], axis: :y
    m
  end

  def self.key(color)
    m = new
    m.box 0, 0, 0, 0.9, 0.9, 0.9, color, color.map { |c| c * 0.7 }
    m.box 0, 0, 0, 0.35, 1.5, 0.35, [255, 255, 255], emissive: true
    m
  end

  def self.missile
    m = new
    m.bipyramid 4, 0.35, 1.2, 0.8, [[200, 200, 210], [140, 140, 150]]
    m
  end
end

MESHES = {
  drone:   Mesh.drone,
  hunter:  Mesh.hunter,
  brute:   Mesh.brute,
  core:    Mesh.reactor_core,
  frame:   Mesh.reactor_frame,
  missile: Mesh.missile,
  shield:  Mesh.pickup([60, 140, 255]),
  energy:  Mesh.pickup([255, 220, 50]),
  missiles: Mesh.pickup([220, 60, 60]),
  blue_key: Mesh.key([50, 110, 255]),
  red_key:  Mesh.key([240, 50, 50])
}
