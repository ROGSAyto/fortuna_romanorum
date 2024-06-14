local CustomBiomeCallHandler = class()

function CustomBiomeCallHandler:custom_biome_type_heights(session, response)
   if stonehearth.world_generation and stonehearth.world_generation._biome_generation_data and stonehearth.world_generation._biome_generation_data._terrain_info and stonehearth.world_generation._biome_generation_data._terrain_info.custom_parameters and stonehearth.world_generation._biome_generation_data._terrain_info.custom_parameters.typeHeights then
      return { typeHeights = stonehearth.world_generation._biome_generation_data._terrain_info.custom_parameters.typeHeights }
   end
   return { typeHeights = { water=0, plains=1, foothills=2, mountains=3 } }
end

return CustomBiomeCallHandler