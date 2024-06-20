local GetClam = class()

GetClam.name = 'get a clam'
GetClam.does = 'fortuna_romanorum:get_clam'
GetClam.args = { }
GetClam.version = 2
GetClam.priority = 1

function make_is_available_clam_fn(ai_entity)
   local player_id = ai_entity:get_player_id()

   return stonehearth.ai:filter_from_key('fortuna_romanorum:get_clam', player_id,
      function(target)
         if target:get_player_id() ~= player_id then
            return false
         end
         local clam_spawner = target:get_component('fortuna_romanorum:clam_spawner')
         if clam_spawner then
            return clam_spawner:harvestable()
         end
         return false
      end
      )
end

local ai = stonehearth.ai
return ai:create_compound_action(Getclam)
:execute('stonehearth:drop_carrying_now', {})
:execute('stonehearth:goto_entity_type', {
   filter_fn = ai.CALL(make_is_available_clam_fn, ai.ENTITY),
   description = 'get a clam'
})
:execute('stonehearth:reserve_entity', { entity = ai.PREV.destination_entity })
:execute('fortuna_romanorum:get_clam_adjacent', { trap = ai.PREV.entity })
