require 'app/vec.rb'
require 'app/level.rb'
require 'app/level_data.rb'
require 'app/renderer.rb'
require 'app/meshes.rb'
require 'app/entities.rb'
require 'app/automap.rb'
require 'app/game.rb'

def tick args
  $game ||= Game.new
  $game.args = args
  $game.tick
end

def reset args
  $game = nil
end


