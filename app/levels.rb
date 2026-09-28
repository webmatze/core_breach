require 'app/levels/mine.rb'
require 'app/levels/deep_core.rb'

# Level definitions in play order. Each is a module with TITLE, SIZE,
# COUNTDOWN, OBJECTIVE, MESSAGES and build(level).
module Levels
  ALL = [Mine, DeepCore]
end
