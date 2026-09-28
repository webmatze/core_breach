D3D_ROOT = 'lib/d3d' unless Object.const_defined?(:D3D_ROOT)
require 'lib/d3d/d3d.rb'

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



