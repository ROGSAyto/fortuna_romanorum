local Entity = _radiant.om.Entity

local GetClamAdjacent = radiant.class()
GetClamAdjacent.name = 'harvest clam trap adjacent'
GetClamAdjacent.does = 'fortuna_romanorum:get_clam_adjacent'
GetClamAdjacent.args = {
	trap = Entity
}
GetClamAdjacent.priority = 0

function GetClamAdjacent:start(ai, entity, args)
	local clam_spawner = args.trap:get_component('fortuna_romanorum:clam_spawner')
	local status_text_key = 'stonehearth:ai.actions.status_text.harvest_resource'
	ai:set_status_text_key(status_text_key, { target = args.trap })
end

function GetClamAdjacent:run(ai, entity, args)
	local clam_trap = args.trap

	local clam_spawner = clam_trap:get_component('fortuna_romanorum:clam_spawner')
	if not clam_spawner:harvestable() then
		ai:abort('clam_trap is not currently harvestable')
	end

	radiant.entities.turn_to_face(entity, clam_trap)
	ai:execute('stonehearth:run_effect', { effect = "fiddle" })

	local location = radiant.entities.get_world_grid_location(entity)
	local spawned_item = clam_spawner:spawn_resource(entity, location)

	radiant.events.trigger_async(entity, 'stonehearth:gather_renewable_resource',
		{harvested_target = clam_trap, spawned_item = spawned_item})

end

return GetClamAdjacent
