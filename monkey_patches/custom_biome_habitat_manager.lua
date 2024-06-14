-- local HabitatManager = require 'stonehearth.services.server.world_generation.habitat_manager'
CustomHabitatManager = class()

function CustomHabitatManager:_get_habitat_type(terrain_type, feature_name)
   local before_features, after_features = self._landscaper:_get_habitat_mappings()
   for key, value in pairs(before_features) do
      if terrain_type == key then
         return value
      end
   end
   if self._landscaper:is_water_feature(feature_name) then
      return 'water'
   end
   if self._landscaper:is_forest_feature(feature_name) then
      return 'forest'
   end
   if feature_name ~= nil then
      return 'occupied'
   end
   for key, value in pairs(after_features) do
      if terrain_type == key then
         return value
      end
   end
   error('Unable to derive habitat_type')
   return 'none'
end

return CustomHabitatManager