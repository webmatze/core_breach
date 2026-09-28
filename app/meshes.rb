# Low poly models for robots, the reactor and pickups, built with D3D::FlatMesh.
# All designs are original. Local space: +x right, +y up, +z forward.
module Models
  # Hovering sentry: diamond body, two swept fins and a glowing sensor.
  def self.drone
    m = D3D::FlatMesh.new
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
    m = D3D::FlatMesh.new
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
    m = D3D::FlatMesh.new
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
    m = D3D::FlatMesh.new
    m.bipyramid 8, 4.0, 5.0, 5.0, [[255, 150, 40], [255, 90, 20]], axis: :y, emissive: true
    m
  end

  def self.reactor_frame
    m = D3D::FlatMesh.new
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
    m = D3D::FlatMesh.new
    dark = color.map { |c| c * 0.6 }
    m.bipyramid 4, 1.0, 1.3, 1.3, [color, dark], axis: :y
    m
  end

  def self.key(color)
    m = D3D::FlatMesh.new
    m.box 0, 0, 0, 0.9, 0.9, 0.9, color, color.map { |c| c * 0.7 }
    m.box 0, 0, 0, 0.35, 1.5, 0.35, [255, 255, 255], emissive: true
    m
  end

  def self.missile
    m = D3D::FlatMesh.new
    m.bipyramid 4, 0.35, 1.2, 0.8, [[200, 200, 210], [140, 140, 150]]
    m
  end
end

MESHES = {
  drone:   Models.drone,
  hunter:  Models.hunter,
  brute:   Models.brute,
  core:    Models.reactor_core,
  frame:   Models.reactor_frame,
  missile: Models.missile,
  shield:  Models.pickup([60, 140, 255]),
  energy:  Models.pickup([255, 220, 50]),
  missiles: Models.pickup([220, 60, 60]),
  blue_key: Models.key([50, 110, 255]),
  yellow_key: Models.key([240, 200, 40]),
  red_key:  Models.key([240, 50, 50])
}
