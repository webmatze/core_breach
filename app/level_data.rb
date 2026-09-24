# Layout of the mine (level 1). Coordinates are cell indices (i = x, j = y/up, k = z).
#
#   Upper level:  hangar -> tunnel -> cavern one -> side passage -> blue key vault
#   Blue hatch in the floor of cavern one drops into the lava cavern (lower level)
#   Lava cavern -> east tunnel -> cavern three (red key high in the ceiling)
#   Red door -> reactor chamber. Destroying the reactor opens the escape hatch
#   in the chamber ceiling, leading to the exit.
module LevelData
  METAL_LIGHT = [1.0, 1.0, 1.05]
  ROCK_LIGHT  = [0.78, 0.7, 0.6]
  DARK_LIGHT  = [0.6, 0.64, 0.78]
  LAVA_LIGHT  = [1.15, 0.62, 0.4]
  TECH_LIGHT  = [0.8, 0.92, 1.15]
  CORE_LIGHT  = [1.05, 0.9, 0.8]

  def self.build(l)
    rng = Lcg.new(1995)

    # --- upper level -------------------------------------------------------
    l.carve 2, 7, 9, 12, 2, 9, :metal, METAL_LIGHT             # hangar
    l.carve 4, 5, 10, 11, 10, 17, :rock, ROCK_LIGHT            # tunnel a
    l.carve 1, 13, 8, 14, 18, 28, :rock, ROCK_LIGHT            # cavern one
    l.fill 6, 7, 8, 14, 22, 23                                 # pillar
    l.fill 10, 10, 12, 14, 20, 20                              # stalactites
    l.fill 3, 3, 13, 14, 21, 21
    l.fill 11, 12, 8, 9, 26, 27                                # boulder
    l.carve 14, 25, 10, 11, 22, 23, :rock_dark, DARK_LIGHT     # side passage
    l.carve 20, 21, 12, 13, 22, 23, :rock_dark, DARK_LIGHT     # bump in passage
    l.carve 26, 31, 9, 13, 19, 26, :tech, TECH_LIGHT           # blue key vault
    l.fill 28, 29, 9, 9, 22, 23                                # pedestal

    # --- blue hatch down to the lower level ---------------------------------
    l.carve 3, 3, 5, 7, 27, 27, :metal, METAL_LIGHT

    # --- lower level --------------------------------------------------------
    l.carve 1, 12, 1, 4, 27, 38, :lava, LAVA_LIGHT             # lava cavern
    l.carve 5, 10, 5, 6, 31, 36, :lava, LAVA_LIGHT             # dome
    l.fill 5, 6, 1, 4, 32, 33                                  # lava pillar
    l.carve 13, 27, 2, 3, 33, 34, :rock_dark, DARK_LIGHT       # east tunnel
    l.carve 18, 19, 1, 1, 33, 34, :rock_dark, DARK_LIGHT       # dip
    l.carve 26, 27, 2, 3, 35, 35, :rock_dark, DARK_LIGHT
    l.carve 26, 42, 1, 7, 36, 46, :rock_dark, DARK_LIGHT       # cavern three
    l.fill 31, 32, 1, 7, 40, 41                                # pillars
    l.fill 37, 37, 1, 5, 42, 43
    l.carve 28, 29, 8, 9, 44, 45, :tech, TECH_LIGHT            # red key nook

    # --- reactor --------------------------------------------------------------
    l.carve 36, 45, 1, 9, 20, 32, :tech, CORE_LIGHT            # reactor chamber
    l.carve 40, 40, 4, 4, 33, 35, :metal, METAL_LIGHT          # red door tunnel

    # --- escape route -----------------------------------------------------------
    l.carve 44, 44, 10, 14, 21, 21, :metal, METAL_LIGHT
    l.carve 33, 44, 14, 14, 21, 21, :metal, METAL_LIGHT
    l.carve 33, 33, 14, 14, 22, 31, :metal, METAL_LIGHT
    l.mark_exit 33, 14, 30
    l.mark_exit 33, 14, 31

    # --- doors ------------------------------------------------------------------
    l.add_door 3, 7, 27, :blue
    l.add_door 40, 4, 35, :red
    l.add_door 44, 10, 21, :exit

    # --- organic caverns ---------------------------------------------------------
    l.roughen 1, 13, 8, 14, 18, 28, 26, rng
    l.roughen 1, 12, 1, 4, 27, 38, 18, rng
    l.roughen 26, 42, 1, 7, 36, 46, 30, rng

    # --- inhabitants ---------------------------------------------------------------
    l.set_player_start [5.0 * CS, 11.0 * CS, 3.0 * CS]
    l.set_reactor [41.0 * CS, 5.0 * CS, 26.5 * CS]

    l.spawn :missiles, 6, 10, 8
    l.spawn :drone, 4, 11, 25
    l.spawn :drone, 11, 11, 20
    l.spawn :hunter, 9, 12, 27
    l.spawn :energy, 2, 9, 19

    l.spawn :hunter, 20, 12, 22
    l.spawn :shield, 26, 10, 19
    l.spawn :drone, 27, 11, 20
    l.spawn :drone, 30, 12, 25
    l.spawn :brute, 27, 11, 24
    l.spawn :blue_key, 28, 11, 22

    l.spawn :drone, 7, 2, 29
    l.spawn :drone, 10, 3, 36
    l.spawn :hunter, 2, 2, 36
    l.spawn :brute, 8, 5, 34
    l.spawn :shield, 11, 2, 28
    l.spawn :missiles, 2, 2, 37

    l.spawn :hunter, 17, 2, 33
    l.spawn :hunter, 24, 3, 34

    l.spawn :drone, 29, 4, 39
    l.spawn :drone, 39, 5, 44
    l.spawn :brute, 34, 3, 38
    l.spawn :hunter, 40, 6, 40
    l.spawn :hunter, 27, 3, 45
    l.spawn :energy, 41, 2, 37
    l.spawn :shield, 35, 2, 45
    l.spawn :red_key, 28, 9, 44

    l.spawn :drone, 37, 7, 22
    l.spawn :drone, 44, 7, 30
    l.spawn :brute, 38, 3, 31
    l.spawn :missiles, 45, 2, 20
    l.spawn :shield, 44, 2, 31
  end
end
