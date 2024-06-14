-- local Array2D = require 'stonehearth.services.server.world_generation.array_2D'
-- local Biome = require 'stonehearth.services.server.world_generation.biome'
-- local log = radiant.log.create_logger('world_generation')

-- local OverviewMap = require 'stonehearth.services.server.world_generation.overview_map'
local CustomOverviewMap = class()

-- placeholder density function
function CustomOverviewMap:_get_wildlife_density(i, j, elevation_map)
   local biome = self._biome
   local radius = self._radius
   local length = 2*radius+1
   local start_a, start_b, width, height, elevation, terrain_type
   local sum = 0

   local function get_wildlife_density_table(biome_instance)
      local terrain_value = {}
      if biome_instance._terrain_info.custom_types then
         for key, value in pairs(biome_instance._terrain_info.custom_types) do
            terrain_value[key] = value.wildlife_density
         end
      else
         terrain_value = {
            plains = 1.0,
            foothills = 1.1,
            mountains = 0.1
         }
      end
      return terrain_value
   end

   local terrain_value = get_wildlife_density_table(biome)

   start_a, start_b, width, height = elevation_map:bound_block(i-radius, j-radius, length, length)

   -- iterate instead of using visit_block as we may want to incorporate feature_map later
   for b=start_b, start_b+height-1 do
      for a=start_a, start_a+width-1 do
         elevation = elevation_map:get(a, b)
         terrain_type = biome:get_terrain_type(elevation)
         if terrain_value[terrain_type] then
            sum = sum + terrain_value[terrain_type]
         end
      end
   end

   local density = sum / (width*height)
   local score = self:_density_to_score(density)
   return score
end

function CustomOverviewMap:_get_mineral_density(i, j, elevation_map)
   local biome = self._biome
   local radius = self._radius
   local length = 2*radius+1
   local start_a, start_b, width, height
   local sum = 0

   local function get_mineral_density_table(biome_instance)
      local terrain_value = {}
      if biome_instance._terrain_info.custom_types then
         for key, value in pairs(biome_instance._terrain_info.custom_types) do
            terrain_value[key] = value.mineral_density
         end
      else
         terrain_value = {
            plains = 0.1,
            foothills = 0.4,
            mountains = 1
         }
      end
      return terrain_value
   end

   local terrain_value = get_mineral_density_table(biome)

   start_a, start_b, width, height = elevation_map:bound_block(i-radius, j-radius, length, length)

   elevation_map:visit_block(start_a, start_b, width, height, function(elevation)
         local terrain_type = biome:get_terrain_type(elevation)
         sum = sum + terrain_value[terrain_type]
      end)

   local density = sum / (width*height)
   local score = self:_density_to_score(density)
   return score
end

return CustomOverviewMap
