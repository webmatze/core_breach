# Evaluated inside DragonRuby by tools/screenshots.rb: stages fixed scenes
# from both levels, screenshots each into screens/, then quits.
# Robots and the Warden hold still and only turn towards the ship, and the
# ship can't be hurt, so every run gives the same pictures.

class Game
  attr_accessor :state

  def update_robots
    @robots.each do |rb|
      rb.hit_flash -= DT
      rb.phase += DT
      rb.fwd = V.norm(V.sub(@ship.pos, rb.pos)) unless rb.mount
    end
  end

  def update_boss
    b = @boss
    return unless b
    b.phase += DT
    b.hit_flash -= DT
    b.shield_flash -= DT
    b.fwd = V.norm(V.sub(@ship.pos, b.pos))
  end

  def damage_ship(_amount); end

  # Cell coordinates to world units.
  def cell(i, j, k)
    [i * CS, j * CS, k * CS]
  end

  def place(i, j, k, look_i, look_j, look_k)
    pos = cell(i, j, k)
    @ship.pos = pos
    @ship.pose.look!(V.norm(V.sub(cell(look_i, look_j, look_k), pos)))
    @ship.vel = [0.0, 0.0, 0.0]
  end

  def robot(kind, i, j, k)
    @robots << Robot.new(kind, cell(i, j, k))
  end

  def shoot(from, to, color = [255, 80, 60], owner = :robot)
    dir = V.norm(V.sub(to, from))
    @projectiles << Projectile.new(from, V.scale(dir, 60.0), owner, 0, :laser, color, 1.2)
  end

  def stage(scene)
    case scene
    when :mine
      start_game(0)
      place(26.4, 12.4, 19.3, 29.5, 9.5, 24)
      robot(:drone, 29, 11.5, 24.5)
      robot(:hunter, 30.5, 10.5, 22)
    when :shaft
      start_game(1)
      @robots.reject! { |rb| V.dist2(rb.pos, cell(21, 35.5, 20)) < 60**2 }
      place(21, 35.5, 20, 26, 10, 27)
    when :dark
      start_game(1)
      place(34.5, 16, 15.3, 34.5, 15, 24)
      stick_flare(cell(35.95, 14.4, 21))
      robot(:splitter, 34.6, 15.6, 23.5)
      robot(:mini, 34, 16.4, 20.5)
    when :magma
      start_game(1)
      place(15.5, 5.5, 3, 30, 3, 9)
      robot(:brute, 22, 4, 5.5)
      robot(:drone, 19, 6, 9)
    when :boss
      start_game(1)
      place(24.5, 7.5, 34.4, 24, 6.5, 40)
      robot(:drone, 19, 9, 39)
      @boss.cooldown = 0
      boss_fire(@boss) # the spread fans out over the following frames
    when :escape
      start_game(1)
      @boss.hp = 0
      @pylons = []
      pos = @boss.pos
      @boss = nil
      objective_complete(pos, 0)
      @robots = []
      place(22, 7, 37, 31.5, 12.5, 42.5)
    when :automap
      start_game(1)
    end
    @messages = []
  end

  # Shots fired just before the screenshot, so they're still in the air.
  def late(scene)
    case scene
    when :mine
      shoot(cell(29, 11.5, 24.5), @ship.pos)
      fire_laser
    when :magma
      shoot(cell(22, 4, 5.5), @ship.pos, [255, 120, 40])
    when :boss
      @boss.shield_flash = 0.3
    when :escape
      @messages = @messages.last(1)
    end
  end

  # Flies the camera along a route so the automap has something to show.
  def explore_route(t)
    route = [cell(23.5, 35, 8), cell(23.5, 35, 17), cell(23.5, 30, 23), cell(20, 28, 22), cell(12, 28, 22),
             cell(6, 28, 22), cell(20, 20, 23), cell(31, 16.5, 23.5), cell(34.5, 16, 17), cell(34.5, 16, 26),
             cell(38.5, 16, 29), cell(42.5, 16, 18), cell(24, 8, 23), cell(23.5, 4.5, 14), cell(20, 4, 7),
             cell(30, 4, 8), cell(24, 18, 24)]
    seg = [(t * (route.size - 1)).floor, route.size - 2].min
    f = t * (route.size - 1) - seg
    @ship.pos = V.lerp(route[seg], route[seg + 1], f)
    @ship.pose.look!(V.norm(V.sub(route[seg + 1], route[seg])))
  end
end

SCENES = [
  [:title, 100],
  [:mine, 40],
  [:shaft, 40],
  [:dark, 40],
  [:magma, 40],
  [:boss, 30],
  [:escape, 450],
  [:automap, 260]
].freeze

$shots = { scene: 0, frame: 0, log: [] }

def tick(args)
  s = $shots
  name, frames = SCENES[s[:scene]]
  begin
    $game ||= Game.new
    g = $game
    g.args = args
    g.stage(name) if s[:frame] == 0 && name != :title
    g.late(name) if s[:frame] == frames - 8
    if name == :automap && s[:frame] < 200
      g.explore_route(s[:frame] / 200.0)
    elsif name == :automap && s[:frame] == 200
      map = g.instance_variable_get(:@automap)
      map.open(g.instance_variable_get(:@ship).pose)
      map.distance = 330.0
      g.state = :automap
    end
    g.tick
  rescue Exception => e
    s[:log] << "FAIL #{name}: #{e.class}: #{e.message} | #{e.backtrace.to_a.first(6).join(' | ')}"
    s[:frame] = frames
  end
  if s[:frame] == frames - 1
    args.outputs.screenshots << { x: 0, y: 0, w: 1280, h: 720, path: "screens/#{name}.png", a: 255 }
  end
  s[:frame] += 1
  return if s[:frame] <= frames

  s[:scene] += 1
  s[:frame] = 0
  return if s[:scene] < SCENES.size

  s[:log] << 'scenes ok' if s[:log].empty?
  $gtk.write_file('screens/report.txt', s[:log].join("\n") + "\n")
  $gtk.request_quit
end
