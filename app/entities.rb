# Game objects. Kept as plain data holders; the behaviour lives in Game.

class Ship
  RADIUS = 2.4

  attr_accessor :vel, :shields, :energy, :missiles, :fire_cooldown, :missile_cooldown,
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
  STATS = {
    drone:  { hp: 30,  radius: 2.4, speed: 20, turn: 2.4, fire: 1.5, score: 100 },
    hunter: { hp: 22,  radius: 2.4, speed: 34, turn: 3.2, fire: nil, score: 150 },
    brute:  { hp: 110, radius: 3.6, speed: 11, turn: 1.3, fire: 2.4, score: 300 }
  }

  attr_accessor :kind, :pos, :vel, :fwd, :hp, :cooldown, :alert, :sees, :last_seen,
                :hit_flash, :phase, :contact_cooldown, :think

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
  end

  def stats
    STATS[@kind]
  end

  def radius
    stats[:radius]
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
