# Level 2: the deep core. Coordinates are cell indices (i = x, j = y/up, k = z).
#
#   Arrival dock (top) -> the Great Shaft, a 12x34x12 cell pit with ledges,
#   bridges and armoured wall turrets. Side exits of the shaft:
#     high, west:   gallery -> key room with the BLUE key
#     middle, east: BLUE door -> blackout wing (maze) with the YELLOW key
#     bottom, south: YELLOW door -> magma caverns with the RED key
#     bottom, north: RED door -> core chamber
#   Completing the objective in the core chamber opens the escape vent in its
#   ceiling, which climbs next to the shaft up to the exit.
module Levels
  module DeepCore
    TITLE     = 'The Deep Core'
    SIZE      = [48, 40, 48]
    COUNTDOWN = 60.0
    OBJECTIVE = :reactor
    MESSAGES  = {
      briefing:       'Descend the shaft. Three keys guard the core. Destroy it and climb out.',
      respawn:        'Ship restored at the arrival dock.',
      exit_locked:    'The escape vent stays sealed while the core is intact.',
      objective_done: 'CORE DESTROYED! Escape vent open: ceiling, far right corner from the red door. Follow the green lights!',
      blue_key:       'BLUE key acquired! The blue door is halfway down the shaft, east side. The power is out beyond it: use flares (G).',
      yellow_key:     'YELLOW key acquired! The yellow door is at the bottom of the shaft, south side.',
      red_key:        'RED key acquired! The core lies behind the red door, bottom of the shaft, north side.'
    }

    METAL_LIGHT  = [1.0, 1.0, 1.05]
    SHAFT_LIGHT  = [1.2, 1.2, 1.35]
    AMBER        = [255, 170, 80]
    COLD         = [120, 180, 255]
    ROCK_LIGHT   = [0.78, 0.7, 0.6]
    WING_LIGHT   = [0.05, 0.05, 0.07]    # blacked out: headlight and flares only
    MAGMA_LIGHT  = [1.2, 0.58, 0.36]
    CORE_LIGHT   = [1.05, 0.9, 0.8]

    def self.build(l)
      rng = Lcg.new(2026)

      # --- arrival dock and the way into the shaft ----------------------------
      l.carve 21, 26, 33, 36, 4, 10, :metal, METAL_LIGHT         # arrival dock
      l.carve 22, 25, 34, 35, 11, 17, :metal, METAL_LIGHT        # dock tunnel

      # --- the Great Shaft ------------------------------------------------------
      l.carve 18, 29, 3, 36, 18, 29, :rock_dark, SHAFT_LIGHT
      l.fill 18, 29, 24, 24, 23, 24                              # upper cross-bridge
      l.fill 22, 23, 14, 14, 18, 29                              # lower cross-bridge
      [[18, 20, 30, 30, 26, 28],                                 # ledges on the walls
       [27, 29, 28, 28, 19, 21],
       [18, 19, 20, 20, 19, 22],
       [27, 29, 12, 12, 24, 27],
       [18, 20, 8, 8, 25, 28],
       [26, 29, 6, 6, 18, 19],
       [18, 19, 17, 18, 27, 29]].each { |b| l.fill(*b) }

      # wall lamps down the shaft, alternating sides and colours. Lights shine
      # through rock, so keep lamps more than 65 units from the dark wing (x >= 33).
      [[18.15, 33.5, 21.5, AMBER], [29.85, 30.5, 25.5, COLD], [23.5, 27.5, 18.15, AMBER],
       [18.15, 19.5, 25.5, COLD], [18.15, 15.5, 20.5, AMBER], [24.5, 10.5, 29.85, COLD],
       [18.15, 6.5, 21.5, AMBER], [29.85, 4.5, 27.5, AMBER]].each { |i, j, k, c| l.lamp(i, j, k, c) }

      # --- west gallery and blue key room (high) ------------------------------
      l.carve 11, 17, 27, 29, 21, 23, :rock, ROCK_LIGHT
      l.carve 3, 10, 25, 31, 17, 28, :rock, ROCK_LIGHT
      l.fill 6, 7, 25, 27, 21, 23                                # rock plinth

      # --- blackout wing behind the blue door (middle, east): power is out -----
      l.carve 30, 32, 16, 16, 23, 23, :metal, METAL_LIGHT
      l.carve 33, 44, 13, 19, 15, 31, :tech, WING_LIGHT
      l.fill 36, 37, 13, 19, 15, 26                              # maze walls
      l.fill 40, 41, 13, 19, 20, 31
      l.fill 33, 35, 17, 19, 27, 31

      # --- magma caverns behind the yellow door (bottom, south) ----------------
      l.carve 23, 23, 4, 4, 13, 17, :metal, METAL_LIGHT
      l.carve 14, 34, 1, 8, 2, 12, :lava, MAGMA_LIGHT
      l.fill 19, 20, 1, 8, 6, 7                                  # magma pillars
      l.fill 28, 29, 1, 6, 4, 5
      l.carve 31, 33, 9, 10, 2, 4, :lava, MAGMA_LIGHT            # red key nook

      # --- core chamber behind the red door (bottom, north) ---------------------
      l.carve 23, 23, 4, 4, 30, 33, :metal, METAL_LIGHT
      l.carve 15, 32, 1, 12, 34, 45, :tech, CORE_LIGHT

      # --- escape vent: chamber ceiling -> up next to the shaft -> exit ---------
      l.carve 31, 31, 13, 36, 42, 42, :metal, METAL_LIGHT
      l.carve 31, 36, 36, 36, 42, 42, :metal, METAL_LIGHT
      l.mark_exit 35, 36, 42
      l.mark_exit 36, 36, 42
      l.beacon 31.5, 12.8, 42.5                                # just below the vent opening
      l.beacon 31.5, 24.5, 42.5                                # halfway up
      l.beacon 31.5, 35.5, 42.5                                # top of the climb
      l.beacon 35.5, 36.5, 42.5                                # exit

      # --- doors ------------------------------------------------------------------
      l.add_door 32, 16, 23, :blue
      l.add_door 23, 4, 13, :yellow
      l.add_door 23, 4, 33, :red
      l.add_door 31, 13, 42, :exit

      # --- organic caverns ---------------------------------------------------------
      l.roughen 3, 10, 25, 31, 17, 28, 14, rng
      l.roughen 14, 34, 1, 8, 2, 12, 34, rng

      # --- inhabitants ---------------------------------------------------------------
      l.set_player_start [24.0 * CS, 35.0 * CS, 6.0 * CS]
      l.set_reactor [24.0 * CS, 6.5 * CS, 40.0 * CS]

      l.spawn :missiles, 22, 34, 8
      l.spawn :shield, 25, 34, 8

      # shaft
      l.spawn :drone, 20, 32, 22
      l.spawn :drone, 27, 26, 26
      l.spawn :hunter, 24, 20, 20
      l.spawn :drone, 21, 16, 27
      l.spawn :brute, 26, 9, 22
      l.spawn :hunter, 20, 5, 25
      l.spawn :energy, 19, 21, 21
      l.spawn :missiles, 28, 13, 25
      l.turret 18, 30, 24, :west
      l.turret 29, 23, 20, :east
      l.turret 23, 18, 29, :north
      l.turret 18, 11, 20, :west
      l.turret 29, 8, 27, :east

      # west gallery / blue key room
      l.spawn :drone, 14, 28, 22
      l.spawn :hunter, 5, 29, 19
      l.spawn :drone, 8, 30, 26
      l.spawn :blue_key, 6, 28, 22
      l.spawn :shield, 9, 26, 18
      l.turret 3, 28, 26, :west

      # blackout wing
      l.spawn :hunter, 34, 15, 20
      l.spawn :drone, 38, 16, 29
      l.spawn :splitter, 39, 15, 17
      l.spawn :splitter, 34, 14, 29
      l.spawn :brute, 43, 16, 25
      l.spawn :energy, 34, 14, 16
      l.spawn :yellow_key, 43, 14, 16

      # magma caverns
      l.spawn :drone, 16, 4, 10
      l.spawn :brute, 25, 3, 4
      l.spawn :splitter, 30, 6, 9
      l.spawn :splitter, 16, 3, 9
      l.turret 34, 5, 8, :east
      l.turret 14, 4, 4, :west
      l.spawn :drone, 33, 5, 7
      l.spawn :hunter, 17, 2, 3
      l.spawn :shield, 22, 2, 10
      l.spawn :missiles, 26, 2, 11
      l.spawn :red_key, 32, 10, 3

      # core chamber
      l.spawn :drone, 17, 9, 36
      l.spawn :drone, 30, 9, 44
      l.spawn :brute, 18, 3, 43
      l.spawn :brute, 29, 3, 36
      l.spawn :shield, 16, 2, 44
      l.spawn :energy, 31, 2, 35
    end
  end
end
