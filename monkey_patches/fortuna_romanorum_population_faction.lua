local rng = _radiant.math.get_default_rng()

local PopulationFaction = require 'stonehearth.services.server.population.population_faction'
local FortunaRomanorumPopulationFaction = class()

FortunaRomanorumPopulationFaction._fortuna_romanorum_old_generate_town_name_from_pieces = PopulationFaction.generate_town_name_from_pieces

function FortunaRomanorumPopulationFaction.generate_town_name_from_pieces(town_pieces)
   local composite_name = 'Defaultville'

   --If we do not yet have the town data, then return a default town name
   if town_pieces then
      local prefix_chance = (town_pieces.prefix_chance == nil) and 40 or town_pieces.prefix_chance
      local prefixes = town_pieces.optional_prefix
      local base_names = town_pieces.town_name
      local suffix_chance = (town_pieces.suffix_chance == nil) and 80 or town_pieces.suffix_chance
      local suffix = town_pieces.suffix

      --make a composite
      local target_prefix = prefixes[rng:get_int(1, #prefixes)]
      local target_base = base_names[rng:get_int(1, #base_names)]
      local target_suffix = suffix[rng:get_int(1, #suffix)]

      if target_base then
         composite_name = target_base
      end

      if target_prefix and rng:get_int(1, 100) <= prefix_chance then
         composite_name = target_prefix .. ' ' .. composite_name
      end

      if target_suffix and rng:get_int(1, 100) <= suffix_chance then
         composite_name = composite_name .. target_suffix
      end
   end

   return composite_name
end

return FortunaRomanorumPopulationFaction
