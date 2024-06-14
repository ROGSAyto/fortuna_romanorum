local constants = require 'stonehearth.constants'
-- local Array2D = require 'stonehearth.services.server.world_generation.array_2D'
-- local ScenarioSelector = require 'stonehearth.services.server.world_generation.scenario_selector'
local WeightedSet = require 'stonehearth.lib.algorithms.weighted_set'
-- local Point3 = _radiant.csg.Point3
local log = radiant.log.create_logger('ore_scenario_selector')

-- local OreScenarioSelector = require 'stonehearth.services.server.world_generation.ore_scenario_selector'
local CustomOreScenarioSelector = class()

function CustomOreScenarioSelector:__init(scenario_index, biome,rng)
   self._scenario_index = scenario_index
   self._biome = biome
   self._rng = rng
   self._y_cell_size = constants.mining.Y_CELL_SIZE
   self._terrain_info = self._biome:get_terrain_info()
   self._min_elevation = self._terrain_info.custom_parameters and self._terrain_info.custom_parameters.ore_min_elevation or self._terrain_info[self._biome._terrain_types[1]].height_max
   if type(self._min_elevation) == 'string' then
      self._min_elevation = self._terrain_info[self._min_elevation].height_max
   end
end

-- TODO: This code is heavily ore dependent. Generalize when we have other underground scenarios.
function CustomOreScenarioSelector:place_revealed_scenarios(underground_elevation_map, elevation_map, tile_offset_x, tile_offset_y)
   local max_depth_in_slices = 6
   local weighted_set = WeightedSet(self._rng)

   underground_elevation_map:visit(function(elevation, i, j)
         local weight = math.floor((elevation - self._min_elevation) / self._y_cell_size)
         weight = math.min(weight, max_depth_in_slices)
         if weight > 0 then
            local index = { i = i, j = j }
            weighted_set:add(index, weight)
         end
      end)

   -- take that from ore_vein scenario instead of hardcoding
   -- NOTE: ore_vein.json must have ALL layers specified
   -- If you want one of the ores not to generate at certain layers:
   -- mix desired list into specific scenario JSON with "mixintypes": {"habitat_types": "override"}
   local ore_vein_json = radiant.resources.load_json('stonehearth:scenarios:static:terrain:ore_vein')
   local habitat_volumes = {}
   for i, terrain_type in ipairs(ore_vein_json.habitat_types) do
      habitat_volumes[terrain_type] = weighted_set:get_total_weight()
   end

   local placement_map = self:_create_placement_map(underground_elevation_map)
   local scenarios = self._scenario_index:select_scenarios('underground', 'revealed', habitat_volumes)
   local num_selected = #scenarios
   local num_placed = 0
   log:debug('%d scenarios selected', num_selected)

   -- because the ore scenarios are so big, the latter scenarios get squeezed out
   -- we randomize the order here so that this doesn't bias the distribution
   self:_randomize_scenarios(scenarios)

   for _, properties in pairs(scenarios) do
      -- allow scenarios to overlap tile boundaries for now
      local index = weighted_set:choose_random()
      if not index then
         break
      end

      local elevation = underground_elevation_map:get(index.i, index.j)
      local max_slice = self:_elevation_to_slice_index(elevation) - 1 -- -1 to get to max valid slice
      local min_slice = self:_elevation_to_slice_index(self._min_elevation)
      min_slice = math.max(min_slice, max_slice - (max_depth_in_slices-1)) -- -1 because inclusive range
      local slice_index = self._rng:get_int(min_slice, max_slice)

      -- location of the center of the mother lode
      local location = self:_calculate_location(tile_offset_x, tile_offset_y, index.i, index.j, slice_index)
      local context = { location = location }

      -- origin and size of the scenario in feature and world coordinates
      local i, j, feature_width, feature_length = self:_calculate_feature_params(index.i, index.j, properties)
      local x, y, width, length = self:_feature_to_world_space(tile_offset_x, tile_offset_y, i, j, feature_width, feature_length)

      if self:_is_unoccupied(placement_map, i, j, feature_width, feature_length, slice_index, slice_index) then
         stonehearth.static_scenario:add_scenario(properties, context, x, y, width, length)
         self:_mark_placement_map(placement_map, i, j, feature_width, feature_length, slice_index, slice_index)
         num_placed = num_placed + 1
      end
   end

   log:debug('%d scenarios placed', num_placed)
end

return CustomOreScenarioSelector
