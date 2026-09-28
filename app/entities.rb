# Game objects. Kept as plain data holders; the behaviour lives in Game.

class Ship
  RADIUS = 2.4

  attr_accessor :vel, :shields, :energy, :missiles, :fire_cooldown, :missile_cooldown, :flare_cooldown,
                :laser_side, :alive, :dead_timer, :hit_flash, :spin
  attr_reader :pose

  def initialize(pos)
    @shields = 100.0
    @energy = 100.0
    @missiles = 5
    respawn(pos)
  end

  def respawn(pos)
    @pose = D3D::Pose.new(pos, [0.0, 0.0, 1.0])
    @vel = [0.0, 0.0, 0.0]
    @spin = [0.0, 0.0, 0.0] # pitch, yaw, roll velocity
    @fire_cooldown = 0
    @missile_cooldown = 0
    @flare_cooldown = 0
    @laser_side = 1
    @alive = true
    @dead_timer = 0
    @hit_flash = 0
  end

  def pos
    @pose.position
  end

  def pos=(p)
    @pose.position = p
  end

  def right
    @pose.right
  end

  def up
    @pose.up
  end

  def fwd
    @pose.fwd
  end
end

class Robot
  # ram: contact damage for robots that fly into the ship.
  # armor: damage multiplier per projectile kind (missing = 1.0).
  # stationary: never moves, only turns (wall turrets).
  STATS = {
    drone:    { hp: 30,  radius: 2.4, speed: 20, turn: 2.4, fire: 1.5, score: 100 },
    hunter:   { hp: 22,  radius: 2.4, speed: 34, turn: 3.2, fire: nil, score: 150, ram: 12 },
    brute:    { hp: 110, radius: 3.6, speed: 11, turn: 1.3, fire: 2.4, score: 300 },
    turret:   { hp: 60,  radius: 2.6, speed: 0,  turn: 1.8, fire: 1.6, score: 200, range: 80,
                armor: { laser: 0.25 }, stationary: true },
    splitter: { hp: 40,  radius: 3.0, speed: 15, turn: 2.0, fire: nil, score: 200, ram: 10 },
    mini:     { hp: 10,  radius: 1.5, speed: 42, turn: 4.0, fire: nil, score: 50, ram: 6, scale: 0.6 }
  }

  attr_accessor :kind, :pos, :vel, :fwd, :hp, :cooldown, :alert, :sees, :last_seen,
                :hit_flash, :phase, :contact_cooldown, :think, :mount, :burst

  def initialize(kind, pos)
    @kind = kind
    @pos = pos.dup
    @vel = [0.0, 0.0, 0.0]
    @fwd = V.norm([rand - 0.5, 0.0, rand - 0.5])
    @hp = stats[:hp]
    @cooldown = 1.0 + rand
    @alert = 0
    @sees = false
    @last_seen = nil
    @hit_flash = 0
    @phase = rand * 10
    @contact_cooldown = 0
    @think = rand(10)
    @mount = nil # wall normal of a mounted turret
    @burst = 0
  end

  def stats
    STATS[@kind]
  end

  def radius
    stats[:radius]
  end

  def scale
    stats[:scale] || 1.0
  end

  def max_hp
    stats[:hp]
  end
end

class Reactor
  RADIUS = 6.5

  attr_accessor :pos, :hp, :cooldown, :hit_flash, :destroyed, :spin

  def initialize(pos)
    @pos = pos
    @hp = 400
    @cooldown = 2.0
    @hit_flash = 0
    @destroyed = false
    @spin = 0
  end
end

class Projectile
  attr_accessor :pos, :vel, :owner, :damage, :kind, :life, :color, :size, :fwd

  def initialize(pos, vel, owner, damage, kind, color, size, life = 3.0)
    @pos = pos
    @vel = vel
    @owner = owner
    @damage = damage
    @kind = kind
    @color = color
    @size = size
    @life = life
    @fwd = V.norm(vel)
  end
end

class Pickup
  attr_accessor :kind, :pos, :phase

  def initialize(kind, pos)
    @kind = kind
    @pos = pos
    @phase = rand * 6
  end
end

class Particle
  attr_accessor :pos, :vel, :life, :max_life, :size, :grow, :color

  def initialize(pos, vel, life, size, grow, color)
    @pos = pos
    @vel = vel
    @life = life
    @max_life = life
    @size = size
    @grow = grow
    @color = color
  end
end

# A flare stuck to a wall: a flickering light that burns out.
class Flare
  attr_accessor :pos, :life, :phase

  def initialize(pos, life)
    @pos = pos
    @life = life
    @phase = rand * 10
  end
end
