local Array2D = require 'stonehearth.services.server.world_generation.array_2D'
-- local FilterFns = require 'stonehearth.services.server.world_generation.filter.filter_fns'
-- local Histogram = require 'stonehearth.lib.algorithms.histogram'
-- local RandomNumberGenerator = _radiant.math.RandomNumberGenerator
-- local log = radiant.log.create_logger('world_generation')

-- local BlueprintGenerator = require 'stonehearth.services.server.world_generation.blueprint_generator'
local CustomBlueprintGenerator = class()

--used in tile based map storing
function CustomBlueprintGenerator:__init(biome)
   self._terrain_info = biome:get_terrain_info()
   self._lowest_terrain = biome:get_terrain_type(0) or 'plains'
end

function CustomBlueprintGenerator:get_empty_blueprint(width, height, terrain_type)
   if terrain_type == nil then
      terrain_type = self._lowest_terrain
   end

   local blueprint = Array2D(width, height)
   local i, j, tile_info

   for j=1, blueprint.height do
      for i=1, blueprint.width do
         tile_info = {}
         tile_info.generated = false
         blueprint:set(i, j, tile_info)
      end
   end

   return blueprint
end

return CustomBlueprintGenerator
