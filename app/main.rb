D3D_ROOT = 'lib/d3d' unless Object.const_defined?(:D3D_ROOT)
require 'lib/d3d/d3d.rb'

# mruby's default generational GC runs a full collection every few frames
# (frame time spikes); incremental mode spreads the work and is faster too.
GC.generational_mode = false if GC.respond_to?(:generational_mode=)

# Optional d3d C extension (DragonRuby Pro, built with tools/build_ext.sh);
# the engine falls back to pure Ruby when it isn't available.
D3D::Native.load

# Short names for the engine helpers used throughout the game.
V = D3D::V unless Object.const_defined?(:V)
Lcg = D3D::Lcg unless Object.const_defined?(:Lcg)

def clamp(v, lo, hi)
  D3D.clamp(v, lo, hi)
end

require 'app/level.rb'
require 'app/levels.rb'
require 'app/meshes.rb'
require 'app/entities.rb'
require 'app/game.rb'

def tick args
  $game ||= Game.new
  $game.args = args
  $game.tick
end

def reset args
  $game = nil
end



