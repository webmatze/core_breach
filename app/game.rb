class Game
  DT              = 1.0 / 60
  THRUST          = 115.0
  DRAG            = 2.9
  TURN_RATE       = 2.3
  MOUSE_SENS      = 0.0032
  COUNTDOWN       = 50.0
  LASER_SPEED     = 190.0
  LASER_DAMAGE    = 7
  LASER_COST      = 0.45
  MISSILE_SPEED   = 95.0
  MISSILE_DAMAGE  = 55
  MISSILE_SPLASH  = 16.0
  PICKUP_RADIUS   = 5.0
  TITLE           = 'CORE BREACH'

  attr_accessor :args

  def initialize
    @state = :title
    @title_time = 0
    @invert_mouse = false
    @show_fps = false
    setup_level
  end

  # ================================================================= setup

  def setup_level
    @level = Level.new
    @renderer = Renderer.new(@level)
    @ship = Ship.new(@level.player_start)
    @lives = 3
    @score = 0
    @keys = {}
    @robots = []
    @pickups = []
    @projectiles = []
    @particles = []
    @lights = []
    @messages = []
    @countdown = nil
    @shake = 0
    @damage_flash = 0
    @pickup_flash = 0
    @play_time = 0
    @door_msg_cooldown = 0
    @kills = 0
    @level.spawns.each do |kind, pos|
      pos = find_open(pos)
      if Robot::STATS[kind]
        @robots << Robot.new(kind, pos)
      else
        @pickups << Pickup.new(kind, pos)
      end
    end
    @reactor = Reactor.new(@level.reactor_pos)
  end

  # Moves a spawn point out of rock if level roughening buried it.
  def find_open(pos)
    return pos unless @level.solid_at?(pos)
    [[0, CS, 0], [0, -CS, 0], [CS, 0, 0], [-CS, 0, 0], [0, 0, CS], [0, 0, -CS],
     [0, 2 * CS, 0], [0, -2 * CS, 0]].each do |o|
      p = V.add(pos, o)
      return p unless @level.solid_at?(p)
    end
    pos
  end

  def start_game
    setup_level
    @state = :playing
    grab_mouse(true)
    message 'Find the blue key. Destroy the reactor. Escape.', 6
    play :door
  end

  # ================================================================= main loop

  def tick
    args.outputs.background_color = [0, 0, 0]
    kb = args.inputs.keyboard
    @show_fps = !@show_fps if kb.key_down.f1

    case @state
    when :title
      tick_title
    when :playing
      if kb.key_down.escape || args.inputs.controller_one.key_down.start
        @state = :paused
        grab_mouse(false)
      else
        update_play
      end
      render_play
    when :paused
      render_play
      render_pause
    when :gameover, :victory
      render_play
      render_end
    end

    if @show_fps
      args.outputs.labels << { x: 1270, y: 710, text: "#{args.gtk.current_framerate.round} fps  #{@renderer.triangle_count} tris",
                               anchor_x: 1, r: 255, g: 255, b: 255, size_px: 16 }
    end
  end

  def grab_mouse(on)
    args.gtk.set_mouse_grab(on ? 2 : 0)
  end

  # ================================================================= title

  def tick_title
    @title_time += 1
    t = @title_time / 60.0
    # slow flythrough of cavern one
    pos = [70.0 + Math.sin(t * 0.21) * 38, 110.0 + Math.sin(t * 0.33) * 18, 232.0 + Math.cos(t * 0.21) * 30]
    fwd = V.norm([Math.cos(t * 0.17), Math.sin(t * 0.23) * 0.25, Math.sin(t * 0.17)])
    right, up = V.basis_from_forward(fwd)
    right, up = V.rotate_pair(right, up, Math.sin(t * 0.3) * 0.25)
    render_world(pos, right, up, fwd)

    out = args.outputs.primitives
    out << { x: 0, y: 0, w: 1280, h: 720, r: 0, g: 0, b: 0, a: 110, path: :solid, primitive_marker: :sprite }
    out << { x: 640, y: 560, text: TITLE, size_px: 96, anchor_x: 0.5, anchor_y: 0.5,
             r: 255, g: 140 + (Math.sin(t * 3) * 40).to_i, b: 40, primitive_marker: :label }
    out << { x: 640, y: 490, text: 'a six degrees of freedom mine shooter', size_px: 26, anchor_x: 0.5,
             anchor_y: 0.5, r: 200, g: 200, b: 210, primitive_marker: :label }

    lines = [
      ['Mouse / Arrows', 'pitch and yaw'],
      ['W S', 'thrust forward / reverse'],
      ['A D', 'slide left / right'],
      ['R F', 'slide up / down'],
      ['Q E', 'roll'],
      ['Left click / Space', 'lasers'],
      ['Right click / Ctrl', 'concussion missile'],
      ['I', 'invert mouse'],
      ['Esc', 'pause']
    ]
    lines.each_with_index do |(k, v), n|
      y = 410 - n * 28
      out << { x: 620, y: y, text: k, size_px: 22, anchor_x: 1, r: 255, g: 210, b: 120, primitive_marker: :label }
      out << { x: 650, y: y, text: v, size_px: 22, r: 220, g: 220, b: 220, primitive_marker: :label }
    end
    if @title_time.idiv(30).even?
      out << { x: 640, y: 110, text: 'Press ENTER or click to launch', size_px: 30, anchor_x: 0.5,
               r: 255, g: 255, b: 255, primitive_marker: :label }
    end
    out << { x: 640, y: 50, text: 'Gamepad: sticks to fly, triggers to fire, bumpers to roll, A/B slide up/down',
             size_px: 18, anchor_x: 0.5, r: 150, g: 150, b: 160, primitive_marker: :label }

    start = args.inputs.keyboard.key_down.enter || args.inputs.mouse.click ||
            args.inputs.controller_one.key_down.start || args.inputs.controller_one.key_down.a
    start_game if start
  end

  # ================================================================= update

  def update_play
    @play_time += DT
    handle_flight_input if @ship.alive
    update_ship
    update_robots
    update_reactor
    update_projectiles
    update_particles
    update_lights
    update_countdown
    @messages.each { |m| m[:time] -= DT }
    @messages.reject! { |m| m[:time] <= 0 }
    @shake *= 0.9
    @damage_flash *= 0.9
    @pickup_flash *= 0.9
    @door_msg_cooldown -= DT
  end

  def handle_flight_input
    kb = args.inputs.keyboard
    ms = args.inputs.mouse
    pad = args.inputs.controller_one
    s = @ship

    @invert_mouse = !@invert_mouse if kb.key_down.i
    message(@invert_mouse ? 'Mouse inverted' : 'Mouse normal', 1.5) if kb.key_down.i

    # --- rotation: keyboard/gamepad rates are smoothed, mouse is direct
    want_pitch = 0.0
    want_yaw = 0.0
    want_roll = 0.0
    want_pitch += 1 if kb.up_arrow
    want_pitch -= 1 if kb.down_arrow
    want_yaw += 1 if kb.right_arrow
    want_yaw -= 1 if kb.left_arrow
    want_roll += 1 if kb.e
    want_roll -= 1 if kb.q
    want_roll += 1 if pad.r1
    want_roll -= 1 if pad.l1
    rx = pad.right_analog_x_perc || 0
    ry = pad.right_analog_y_perc || 0
    want_yaw += rx if rx.abs > 0.15
    want_pitch += ry if ry.abs > 0.15
    target = [want_pitch * TURN_RATE, want_yaw * TURN_RATE, want_roll * TURN_RATE]
    3.times { |n| s.spin[n] += (target[n] - s.spin[n]) * 0.2 }

    pitch = s.spin[0] * DT
    yaw = s.spin[1] * DT
    roll = s.spin[2] * DT
    mdx = ms.relative_x || 0
    mdy = ms.relative_y || 0
    yaw += mdx * MOUSE_SENS
    pitch += mdy * MOUSE_SENS * (@invert_mouse ? -1 : 1)

    s.fwd, s.right = V.rotate_pair(s.fwd, s.right, yaw) if yaw != 0
    s.fwd, s.up = V.rotate_pair(s.fwd, s.up, pitch) if pitch != 0
    s.up, s.right = V.rotate_pair(s.up, s.right, roll) if roll != 0
    s.orthonormalize!

    # --- translation
    thrust = 0.0
    slide_x = 0.0
    slide_y = 0.0
    thrust += 1 if kb.w
    thrust -= 1 if kb.s
    slide_x += 1 if kb.d
    slide_x -= 1 if kb.a
    slide_y += 1 if kb.r
    slide_y -= 1 if kb.f
    lx = pad.left_analog_x_perc || 0
    ly = pad.left_analog_y_perc || 0
    slide_x += lx if lx.abs > 0.15
    thrust += ly if ly.abs > 0.15
    slide_y += 1 if pad.a
    slide_y -= 1 if pad.b

    acc = V.scale(s.fwd, thrust * THRUST)
    acc = V.madd(acc, s.right, slide_x * THRUST * 0.85)
    acc = V.madd(acc, s.up, slide_y * THRUST * 0.85)
    s.vel = V.madd(s.vel, acc, DT)

    # --- weapons
    s.fire_cooldown -= DT
    s.missile_cooldown -= DT
    fire_primary = kb.space || ms.button_left || pad.r2
    fire_secondary = kb.control || ms.button_right || pad.l2
    fire_laser if fire_primary && s.fire_cooldown <= 0
    fire_missile if fire_secondary && s.missile_cooldown <= 0
  end

  def fire_laser
    s = @ship
    if s.energy < LASER_COST
      message('Energy depleted!', 1) if s.fire_cooldown > -0.05
      s.fire_cooldown = 0.5
      return
    end
    s.energy -= LASER_COST
    s.fire_cooldown = 0.17
    [-1, 1].each do |side|
      origin = V.madd(V.madd(V.madd(s.pos, s.right, side * 1.4), s.up, -0.8), s.fwd, 1.5)
      vel = V.madd(V.scale(s.fwd, LASER_SPEED), s.vel, 0.5)
      @projectiles << Projectile.new(origin, vel, :player, LASER_DAMAGE, :laser, [255, 60, 60], 1.3, 1.2)
    end
    add_light(V.madd(s.pos, s.fwd, 3), 18, [1.0, 0.3, 0.2], 0.6, 0.08)
    play :laser, 0.35
  end

  def fire_missile
    s = @ship
    if s.missiles <= 0
      message('No missiles!', 1)
      s.missile_cooldown = 0.6
      return
    end
    s.missiles -= 1
    s.missile_cooldown = 0.7
    origin = V.madd(V.madd(s.pos, s.up, -1.5), s.fwd, 2)
    vel = V.madd(V.scale(s.fwd, MISSILE_SPEED), s.vel, 0.5)
    @projectiles << Projectile.new(origin, vel, :player, MISSILE_DAMAGE, :missile, [255, 200, 120], 2.0, 4.0)
    play :missile, 0.6
  end

  def update_ship
    s = @ship
    unless s.alive
      s.dead_timer -= DT
      if s.dead_timer <= 0
        if @lives < 0
          @state = :gameover
          @end_reason = 'Your last ship was destroyed.'
          grab_mouse(false)
        else
          s.respawn(@level.player_start)
          s.shields = 100.0
          s.energy = [s.energy, 100.0].max
          s.missiles = [s.missiles, 3].max
          message 'Ship restored at the hangar.', 3
        end
      end
      return
    end

    s.vel = V.scale(s.vel, 1.0 - DRAG * DT)
    s.pos = V.madd(s.pos, s.vel, DT)
    hit = @level.collide_sphere(s.pos, Ship::RADIUS)
    if hit
      vn = V.dot(s.vel, hit)
      if vn < 0
        s.vel = V.madd(s.vel, hit, -vn * 1.4)
        if vn < -30
          @shake = [@shake, 0.4].max
          play :hit, 0.25
        end
      end
    end
    s.hit_flash -= DT

    # doors
    door = @level.door_near(s.pos, Ship::RADIUS + 1.2)
    if door
      kind = @level.doors[door]
      if kind == :exit
        if @door_msg_cooldown <= 0
          message 'This hatch only opens when the reactor goes critical.', 3
          @door_msg_cooldown = 3
        end
      elsif @keys[kind]
        @level.open_door(door)
        play :door
        message "#{kind.to_s.upcase} door opened.", 2
      elsif @door_msg_cooldown <= 0
        message "You need the #{kind.to_s.upcase} key to open this door.", 3
        @door_msg_cooldown = 3
      end
    end

    # pickups
    @pickups.reject! do |pk|
      next false if V.dist2(pk.pos, s.pos) > PICKUP_RADIUS * PICKUP_RADIUS
      collect(pk)
    end

    # exit
    if @countdown && @level.exit_at?(s.pos)
      @state = :victory
      bonus = (@countdown * 100).to_i
      @score += bonus + @ship.shields.to_i * 10
      @end_reason = "You escaped with #{@countdown.round(1)}s to spare."
      grab_mouse(false)
      play :pickup
    end
  end

  def collect(pk)
    s = @ship
    case pk.kind
    when :shield
      return false if s.shields >= 200
      s.shields = [s.shields + 25, 200].min
      message 'Shield boost!', 2
    when :energy
      return false if s.energy >= 200
      s.energy = [s.energy + 30, 200].min
      message 'Energy boost!', 2
    when :missiles
      s.missiles += 4
      message '4 concussion missiles!', 2
    when :blue_key
      @keys[:blue] = true
      message 'BLUE key acquired! The blue hatch is in the floor of the big cavern.', 5
    when :red_key
      @keys[:red] = true
      message 'RED key acquired! The reactor lies behind the red door.', 5
    end
    @score += 50
    @pickup_flash = 1
    play :pickup, 0.5
    true
  end

  def damage_ship(amount)
    s = @ship
    return unless s.alive
    s.shields -= amount
    s.hit_flash = 0.15
    @damage_flash = [@damage_flash + amount / 25.0, 0.8].min
    @shake = [@shake + amount / 20.0, 1.2].max
    play :hit, 0.5
    return unless s.shields < 0
    s.alive = false
    s.dead_timer = 3.0
    @lives -= 1
    explode(s.pos, 3.0, [255, 160, 60])
    message(@lives >= 0 ? 'Ship destroyed!' : 'Ship destroyed! No ships left.', 3)
  end

  # ================================================================= robots

  def update_robots
    s = @ship
    @robots.each do |rb|
      st = rb.stats
      rb.hit_flash -= DT
      rb.cooldown -= DT
      rb.contact_cooldown -= DT
      rb.phase += DT
      rb.think += 1
      to_p = V.sub(s.pos, rb.pos)
      dist = V.len(to_p)

      if rb.think % 8 == 0
        rb.sees = s.alive && dist < 95 && @level.los?(rb.pos, s.pos)
        if rb.sees
          rb.alert = 5.0
          rb.last_seen = s.pos.dup
        end
      end
      rb.alert -= DT

      desired = [0.0, 0.0, 0.0]
      if rb.alert > 0 && rb.last_seen
        target_dir = V.norm(V.sub(rb.last_seen, rb.pos))
        turn = [st[:turn] * DT, 1.0].min
        rb.fwd = V.norm(V.lerp(rb.fwd, target_dir, turn))
        right, up = V.basis_from_forward(rb.fwd)
        case rb.kind
        when :drone
          if !rb.sees || dist > 34
            desired = V.scale(target_dir, st[:speed])
          elsif dist < 18
            desired = V.scale(target_dir, -st[:speed])
          end
          desired = V.madd(desired, right, Math.sin(rb.phase * 1.3) * st[:speed] * 0.7)
          desired = V.madd(desired, up, Math.cos(rb.phase * 0.9) * st[:speed] * 0.3)
        when :hunter
          desired = V.scale(target_dir, st[:speed])
          desired = V.madd(desired, right, Math.sin(rb.phase * 3.0) * 6)
        when :brute
          desired = V.scale(target_dir, st[:speed]) if !rb.sees || dist > 26
        end

        if rb.sees && st[:fire] && rb.cooldown <= 0 && V.dot(rb.fwd, target_dir) > 0.9
          robot_fire(rb, right)
          rb.cooldown = st[:fire] * (0.8 + rand * 0.4)
        end

        if rb.kind == :hunter && s.alive && dist < rb.radius + Ship::RADIUS + 0.6 && rb.contact_cooldown <= 0
          damage_ship(12)
          push = V.norm(to_p)
          s.vel = V.madd(s.vel, push, 35)
          rb.vel = V.madd(rb.vel, push, -30)
          rb.contact_cooldown = 1.0
          explode(V.lerp(rb.pos, s.pos, 0.5), 0.6, [180, 255, 180], false)
        end
      else
        # idle patrol: bob and slowly turn
        rb.fwd = V.norm(V.madd(rb.fwd, V.basis_from_forward(rb.fwd)[0], 0.3 * DT))
        desired = [0.0, Math.sin(rb.phase) * 2.0, 0.0]
      end

      rb.vel = V.lerp(rb.vel, desired, [3.0 * DT, 1.0].min)
      rb.pos = V.madd(rb.pos, rb.vel, DT)
      hit = @level.collide_sphere(rb.pos, rb.radius)
      if hit
        vn = V.dot(rb.vel, hit)
        rb.vel = V.madd(rb.vel, hit, -vn) if vn < 0
      end
    end

    # keep robots from overlapping each other
    @robots.each_with_index do |a, n|
      ((n + 1)...@robots.size).each do |m|
        b = @robots[m]
        min = a.radius + b.radius
        d2 = V.dist2(a.pos, b.pos)
        next if d2 >= min * min || d2 < 1e-6
        d = Math.sqrt(d2)
        push = V.scale(V.sub(a.pos, b.pos), (min - d) / d * 0.5)
        a.pos = V.add(a.pos, push)
        b.pos = V.sub(b.pos, push)
      end
    end
  end

  def robot_fire(rb, right)
    muzzle = V.madd(rb.pos, rb.fwd, rb.radius + 0.5)
    aim = V.norm(V.sub(@ship.pos, muzzle))
    case rb.kind
    when :drone
      @projectiles << Projectile.new(muzzle, V.scale(aim, 62), :enemy, 8, :plasma, [255, 90, 40], 1.8)
    when :brute
      up = V.cross(aim, right)
      [-0.12, 0.0, 0.12].each do |spread|
        dir = V.norm(V.madd(aim, right, spread))
        dir = V.norm(V.madd(dir, up, spread.abs * 0.3))
        @projectiles << Projectile.new(muzzle.dup, V.scale(dir, 52), :enemy, 10, :plasma, [255, 60, 220], 2.2)
      end
    end
    add_light(muzzle, 20, [1.0, 0.4, 0.2], 0.6, 0.1)
    play :robot_shot, 0.4, rb.pos
  end

  def damage_robot(rb, amount)
    rb.hp -= amount
    rb.hit_flash = 0.1
    rb.alert = 6.0
    rb.last_seen = @ship.pos.dup
    return if rb.hp > 0
    @robots.delete(rb)
    @score += rb.stats[:score]
    @kills += 1
    explode(rb.pos, rb.kind == :brute ? 2.2 : 1.4, [255, 170, 70])
    drop = rand
    if drop < 0.22
      @pickups << Pickup.new(:energy, rb.pos.dup)
    elsif drop < 0.4
      @pickups << Pickup.new(:shield, rb.pos.dup)
    elsif drop < 0.48
      @pickups << Pickup.new(:missiles, rb.pos.dup)
    end
  end

  # ================================================================= reactor

  def update_reactor
    r = @reactor
    r.spin += DT
    r.hit_flash -= DT
    return if r.destroyed
    r.cooldown -= DT
    s = @ship
    return unless s.alive && r.cooldown <= 0
    dist = V.dist(s.pos, r.pos)
    return if dist > 90
    return unless @level.los?(r.pos, s.pos)
    r.cooldown = 1.8
    aim = V.norm(V.sub(s.pos, r.pos))
    right, up = V.basis_from_forward(aim)
    muzzle = V.madd(r.pos, aim, Reactor::RADIUS)
    [[0, 0], [-0.1, 0.05], [0.1, 0.05], [0, -0.1]].each do |dx, dy|
      dir = V.norm(V.madd(V.madd(aim, right, dx), up, dy))
      @projectiles << Projectile.new(muzzle.dup, V.scale(dir, 58), :enemy, 11, :plasma, [255, 220, 60], 2.4)
    end
    play :robot_shot, 0.6, r.pos
  end

  def damage_reactor(amount)
    r = @reactor
    return if r.destroyed
    r.hp -= amount
    r.hit_flash = 0.1
    return if r.hp > 0
    r.destroyed = true
    @score += 5000
    @countdown = COUNTDOWN
    explode(r.pos, 5.0, [255, 200, 90])
    6.times { explode(V.madd(r.pos, V.random_unit, 6), 2.0, [255, 120, 40], false) }
    @shake = 2.0
    exit_door = @level.door_idx(:exit)
    @level.open_door(exit_door) if exit_door
    message 'REACTOR DESTROYED! The escape hatch in the chamber ceiling is open. GET OUT!', 8
  end

  def update_countdown
    return unless @countdown
    before = @countdown
    @countdown -= DT
    @shake = [@shake, 0.25 + (1.0 - @countdown / COUNTDOWN) * 0.6].max
    play(:alarm, 0.35) if before.floor != @countdown.floor && @countdown.floor.even?
    if rand < 0.05 && @ship.alive
      explode(V.madd(@ship.pos, V.random_unit, 25 + rand * 20), 1.2, [255, 140, 50], false)
    end
    return unless @countdown <= 0
    @countdown = 0
    @state = :gameover
    @end_reason = 'The mine collapsed with you still inside.'
    explode(@ship.pos, 6, [255, 255, 255])
    grab_mouse(false)
  end

  # ================================================================= projectiles

  def update_projectiles
    s = @ship
    @projectiles.reject! do |pr|
      pr.life -= DT
      next true if pr.life <= 0
      steps = 2
      dead = false
      steps.times do
        pr.pos = V.madd(pr.pos, pr.vel, DT / steps)
        if @level.solid_at?(pr.pos)
          impact(pr, nil)
          dead = true
          break
        end
        if pr.owner == :player
          target = @robots.find { |rb| V.dist2(rb.pos, pr.pos) < (rb.radius + pr.size * 0.5)**2 }
          if target
            impact(pr, target)
            dead = true
            break
          end
          if !@reactor.destroyed && V.dist2(@reactor.pos, pr.pos) < Reactor::RADIUS**2
            impact(pr, @reactor)
            dead = true
            break
          end
        elsif s.alive && V.dist2(s.pos, pr.pos) < (Ship::RADIUS + pr.size * 0.4)**2
          damage_ship(pr.damage)
          impact(pr, nil)
          dead = true
          break
        end
      end
      if !dead && pr.kind == :missile && rand < 0.8
        @particles << Particle.new(pr.pos.dup, V.scale(V.random_unit, 2), 0.5, 0.8, 2.0, [70, 60, 55])
      end
      dead
    end
  end

  def impact(pr, target)
    if pr.kind == :missile
      explode(pr.pos, 1.6, [255, 190, 90])
      @robots.dup.each do |rb|
        d = V.dist(rb.pos, pr.pos)
        next if d > MISSILE_SPLASH
        dmg = rb == target ? pr.damage : pr.damage * 0.6 * (1 - d / MISSILE_SPLASH)
        damage_robot(rb, dmg)
      end
      rd = V.dist(@reactor.pos, pr.pos)
      damage_reactor(target == @reactor ? pr.damage : pr.damage * 0.5) if rd < MISSILE_SPLASH + Reactor::RADIUS
      sd = V.dist(@ship.pos, pr.pos)
      damage_ship(20 * (1 - sd / MISSILE_SPLASH)) if sd < MISSILE_SPLASH * 0.7
    else
      if target.is_a?(Robot)
        damage_robot(target, pr.damage)
      elsif target.is_a?(Reactor)
        damage_reactor(pr.damage)
      end
      sparks(pr.pos, pr.color, 5)
      add_light(pr.pos, 14, pr.color.map { |c| c / 255.0 }, 0.8, 0.12)
    end
  end

  # ================================================================= effects

  def explode(pos, size, color, sound = true)
    18.times do
      vel = V.scale(V.random_unit, (6 + rand * 14) * size)
      @particles << Particle.new(pos.dup, vel, 0.4 + rand * 0.5, 1.5 * size, 4.0 * size, color)
    end
    @particles << Particle.new(pos.dup, [0.0, 0.0, 0.0], 0.5, 3 * size, 14 * size, [255, 255, 220])
    add_light(pos, 25 * size, color.map { |c| c / 255.0 }, 1.4, 0.6)
    if sound
      play :explosion, clamp(0.4 * size, 0.3, 1.0), pos
      d = V.dist(pos, @ship.pos)
      @shake = [@shake, size * 0.6 * (1 - d / 80.0)].max if d < 80
    end
  end

  def sparks(pos, color, count)
    count.times do
      @particles << Particle.new(pos.dup, V.scale(V.random_unit, 12 + rand * 18), 0.2 + rand * 0.25, 0.6, -1.0, color)
    end
  end

  def update_particles
    @particles.reject! do |pt|
      pt.life -= DT
      pt.pos = V.madd(pt.pos, pt.vel, DT)
      pt.vel = V.scale(pt.vel, 0.94)
      pt.size = [pt.size + pt.grow * DT, 0.05].max
      pt.life <= 0
    end
  end

  def add_light(pos, radius, color, intensity, life)
    @lights << { pos: pos, radius: radius, color: color, intensity: intensity, base: intensity, life: life, max: life }
  end

  def update_lights
    @lights.reject! do |lt|
      lt[:life] -= DT
      lt[:intensity] = lt[:base] * lt[:life] / lt[:max]
      lt[:life] <= 0
    end
  end

  # ================================================================= messages / sound

  def message(text, time)
    @messages.reject! { |m| m[:text] == text }
    @messages << { text: text, time: time }
    @messages.shift while @messages.size > 3
  end

  def play(name, gain = 0.5, pos = nil)
    if pos
      d = V.dist(pos, @ship.pos)
      return if d > 140
      gain *= 1.0 - d / 140.0
    end
    @sfx_id = (@sfx_id || 0) + 1
    args.audio[:"sfx_#{@sfx_id % 24}"] = { input: "sounds/#{name}.wav", gain: gain }
  end

  # ================================================================= rendering

  def render_play
    s = @ship
    pos = s.pos
    right = s.right
    up = s.up
    fwd = s.fwd
    if @shake > 0.01
      pos = V.madd(pos, V.random_unit, @shake * 0.6)
      right, up = V.rotate_pair(right, up, (rand - 0.5) * @shake * 0.04)
    end
    render_world(pos, right, up, fwd)
    render_hud
  end

  def render_world(pos, right, up, fwd)
    boost = [0.0, 0.0, 0.0]
    if @countdown
      pulse = (Math.sin(@play_time * 8) + 1) * 0.5
      boost = [0.25 * pulse, 0.0, 0.0]
    end
    lights = @lights.dup
    @projectiles.each do |pr|
      lights << { pos: pr.pos, radius: 12, color: pr.color.map { |c| c / 255.0 }, intensity: 0.5 }
    end
    lights = lights.sort_by { |l| V.dist2(l[:pos], pos) }.first(8)

    r = @renderer
    r.begin_frame(pos, right, up, fwd, lights, boost)
    r.draw_level

    @robots.each do |rb|
      next unless V.dist2(rb.pos, pos) < Renderer::FOG**2
      next unless @level.los?(pos, rb.pos, 3.0)
      rgt, u = V.basis_from_forward(rb.fwd)
      flash = rb.hit_flash > 0 ? 0.7 : 0.0
      r.draw_mesh(MESHES[rb.kind], rb.pos, rgt, u, rb.fwd, 1.0, @level.tint_at(rb.pos), flash)
      eye = V.madd(rb.pos, rb.fwd, rb.kind == :brute ? 2.2 : 2.0)
      r.draw_glow(eye, 1.6, 255, 80, 60, 200)
    end

    render_reactor(r, pos)

    @pickups.each do |pk|
      next unless V.dist2(pk.pos, pos) < 90**2
      next unless @level.los?(pos, pk.pos, 3.0)
      pk.phase += DT
      a = pk.phase * 2
      fwd2 = [Math.sin(a), 0.0, Math.cos(a)]
      rgt, u = V.basis_from_forward(fwd2)
      p = V.add(pk.pos, [0, Math.sin(pk.phase * 2) * 0.6, 0])
      mesh = MESHES[pk.kind]
      r.draw_mesh(mesh, p, rgt, u, fwd2, 1.0, [1.2, 1.2, 1.2])
      col = mesh.tris[0].color
      r.draw_glow(p, 5.5, col[0], col[1], col[2], 120)
    end

    @projectiles.each do |pr|
      if pr.kind == :missile
        rgt, u = V.basis_from_forward(pr.fwd)
        r.draw_mesh(MESHES[:missile], pr.pos, rgt, u, pr.fwd, 1.0, [1, 1, 1])
        r.draw_glow(V.madd(pr.pos, pr.fwd, -1.2), 3.0, 255, 180, 80)
      else
        c = pr.color
        r.draw_glow(pr.pos, pr.size * 1.6, c[0], c[1], c[2])
        r.draw_glow(V.madd(pr.pos, pr.fwd, -1.2), pr.size, c[0], c[1], c[2], 160)
        r.draw_glow(pr.pos, pr.size * 0.6, 255, 255, 255)
      end
    end

    @particles.each do |pt|
      f = pt.life / pt.max_life
      c = pt.color
      r.draw_glow(pt.pos, pt.size, c[0], c[1], c[2], (255 * f).to_i)
    end

    r.flush(args.outputs)
  end

  def render_reactor(r, cam)
    rc = @reactor
    return unless V.dist2(rc.pos, cam) < 140**2
    ang = rc.spin * 0.6
    fwd = [Math.sin(ang), 0.0, Math.cos(ang)]
    right, up = V.basis_from_forward(fwd)
    r.draw_mesh(MESHES[:frame], rc.pos, right, up, fwd, 1.0, [1.0, 0.9, 0.8])
    return if rc.destroyed
    ang2 = -rc.spin * 1.7
    fwd2 = [Math.sin(ang2), 0.0, Math.cos(ang2)]
    right2, up2 = V.basis_from_forward(fwd2)
    pulse = 0.9 + Math.sin(rc.spin * 5) * 0.1
    r.draw_mesh(MESHES[:core], rc.pos, right2, up2, fwd2, pulse, [1, 1, 1], rc.hit_flash > 0 ? 0.6 : 0.0)
    r.draw_glow(rc.pos, 22 * pulse, 255, 140, 40, 130)
  end

  # ================================================================= hud

  def render_hud
    out = args.outputs.primitives
    s = @ship

    # crosshair
    if s.alive
      c = s.fire_cooldown > 0 ? [255, 150, 90] : [120, 255, 140]
      [[-18, 0, 10, 2], [8, 0, 10, 2], [0, -18, 2, 10], [0, 8, 2, 10]].each do |x, y, w, h|
        out << { x: 640 + x - (w == 2 ? 1 : 0), y: 360 + y - (h == 2 ? 1 : 0), w: w, h: h,
                 r: c[0], g: c[1], b: c[2], a: 200, path: :solid, primitive_marker: :sprite }
      end
    end

    # overlays
    if @damage_flash > 0.02
      out << { x: 0, y: 0, w: 1280, h: 720, r: 255, g: 30, b: 20, a: (@damage_flash * 150).to_i, path: :solid, primitive_marker: :sprite }
    end
    if @pickup_flash > 0.02
      out << { x: 0, y: 0, w: 1280, h: 720, r: 60, g: 120, b: 255, a: (@pickup_flash * 60).to_i, path: :solid, primitive_marker: :sprite }
    end
    unless s.alive
      out << { x: 0, y: 0, w: 1280, h: 720, r: 0, g: 0, b: 0, a: 120, path: :solid, primitive_marker: :sprite }
    end

    # cockpit strip
    out << { x: 0, y: 0, w: 1280, h: 64, r: 10, g: 12, b: 18, a: 190, path: :solid, primitive_marker: :sprite }
    out << { x: 0, y: 64, w: 1280, h: 2, r: 90, g: 100, b: 130, a: 200, path: :solid, primitive_marker: :sprite }
    gauge(out, 30, 22, 'SHIELDS', s.shields, 200, [70, 140, 255])
    gauge(out, 330, 22, 'ENERGY', s.energy, 200, [255, 210, 60])
    label(out, 640, 44, 'MISSILES', 16, [170, 170, 190], 0.5)
    label(out, 640, 22, s.missiles.to_s, 26, [255, 110, 90], 0.5)
    label(out, 780, 44, 'KEYS', 16, [170, 170, 190])
    { blue: [60, 120, 255], red: [240, 60, 60] }.each_with_index do |(k, col), n|
      x = 780 + n * 34
      if @keys[k]
        out << { x: x, y: 10, w: 26, h: 20, r: col[0], g: col[1], b: col[2], path: :solid, primitive_marker: :sprite }
      else
        out << { x: x, y: 10, w: 26, h: 20, r: col[0], g: col[1], b: col[2], primitive_marker: :border }
      end
    end
    label(out, 920, 44, 'SHIPS', 16, [170, 170, 190])
    label(out, 920, 22, [@lives, 0].max.to_s, 26, [255, 255, 255])
    label(out, 1250, 44, 'SCORE', 16, [170, 170, 190], 1)
    label(out, 1250, 22, @score.to_s, 26, [255, 255, 255], 1)

    reactor_hp = @reactor.destroyed ? 0 : @reactor.hp
    if !@reactor.destroyed && @reactor.hp < 400
      label(out, 640, 690, "REACTOR INTEGRITY #{(reactor_hp / 4.0).ceil}%", 20, [255, 170, 60], 0.5)
    end

    if @countdown
      secs = @countdown.ceil
      flash = (@play_time * 4).to_i.even?
      label(out, 640, 640, format('SELF DESTRUCT  %02d', secs), 44, flash ? [255, 60, 40] : [255, 220, 120], 0.5)
    end

    @messages.each_with_index do |m, n|
      a = clamp(m[:time] * 255, 0, 255).to_i
      label(out, 640, 590 - n * 30, m[:text], 22, [230, 240, 255], 0.5, a)
    end

    unless s.alive
      label(out, 640, 380, 'SHIP DESTROYED', 48, [255, 90, 60], 0.5)
    end
  end

  def gauge(out, x, y, name, value, max, col)
    label(out, x, y + 22, name, 16, [170, 170, 190])
    out << { x: x + 90, y: y - 8, w: 170, h: 16, r: 40, g: 40, b: 50, path: :solid, primitive_marker: :sprite }
    w = (170 * clamp(value, 0, max) / max.to_f).to_i
    out << { x: x + 90, y: y - 8, w: w, h: 16, r: col[0], g: col[1], b: col[2], path: :solid, primitive_marker: :sprite }
    out << { x: x + 90 + 85, y: y - 8, w: 1, h: 16, r: 255, g: 255, b: 255, a: 90, path: :solid, primitive_marker: :sprite }
    label(out, x, y, value.to_i.to_s, 26, col)
  end

  def label(out, x, y, text, size, col, anchor = 0, a = 255)
    out << { x: x, y: y, text: text, size_px: size, anchor_x: anchor, anchor_y: 0.5,
             r: col[0], g: col[1], b: col[2], a: a, primitive_marker: :label }
  end

  def render_pause
    out = args.outputs.primitives
    out << { x: 0, y: 0, w: 1280, h: 720, r: 0, g: 0, b: 0, a: 150, path: :solid, primitive_marker: :sprite }
    label(out, 640, 420, 'PAUSED', 64, [255, 255, 255], 0.5)
    label(out, 640, 340, 'ESC or click to resume   -   T to quit to title', 24, [200, 200, 210], 0.5)
    kb = args.inputs.keyboard
    if kb.key_down.escape || args.inputs.mouse.click || args.inputs.controller_one.key_down.start
      @state = :playing
      grab_mouse(true)
    elsif kb.key_down.t
      @state = :title
      setup_level
    end
  end

  def render_end
    out = args.outputs.primitives
    won = @state == :victory
    out << { x: 0, y: 0, w: 1280, h: 720, r: won ? 0 : 40, g: 0, b: 0, a: 170, path: :solid, primitive_marker: :sprite }
    label(out, 640, 470, won ? 'MINE ESCAPED!' : 'GAME OVER', 72, won ? [120, 255, 140] : [255, 80, 60], 0.5)
    label(out, 640, 390, @end_reason.to_s, 26, [230, 230, 240], 0.5)
    label(out, 640, 340, "Score #{@score}    Robots destroyed #{@kills}    Time #{@play_time.to_i}s", 24,
          [255, 220, 140], 0.5)
    label(out, 640, 250, 'Press ENTER to return to the title screen', 24, [200, 200, 210], 0.5)
    if args.inputs.keyboard.key_down.enter || args.inputs.controller_one.key_down.start
      @state = :title
      setup_level
    end
  end
end
