fortuna_romanorum = {}

local required_mods = {}

local init_patches = {
  fortuna_romanorum_population_faction = 'stonehearth.services.server.population.population_faction',
  custom_biome = 'stonehearth.services.server.world_generation.biome'
}

local coast_patches = {
  custom_biome = 'stonehearth.services.server.world_generation.biome',
  custom_biome_world_generation_service = 'stonehearth.services.server.world_generation.world_generation_service',
  custom_biome_array_2D = 'stonehearth.services.server.world_generation.array_2D',
  custom_biome_blueprint_generator = 'stonehearth.services.server.world_generation.blueprint_generator',
  custom_biome_habitat_manager = 'stonehearth.services.server.world_generation.habitat_manager',
  custom_biome_height_map_renderer = 'stonehearth.services.server.world_generation.height_map_renderer',
  custom_biome_landscaper = 'stonehearth.services.server.world_generation.landscaper',
  custom_biome_micro_map_generator = 'stonehearth.services.server.world_generation.micro_map_generator',
  custom_biome_ore_scenario_selector = 'stonehearth.services.server.world_generation.ore_scenario_selector',
  custom_biome_overview_map = 'stonehearth.services.server.world_generation.overview_map',
  custom_biome_terrain_detailer = 'stonehearth.services.server.world_generation.terrain_detailer'
}

local conditional_patches = {}

function fortuna_romanorum.setup_patching()
  for key, value in pairs(conditional_patches) do
    if fortuna_romanorum.is_mod_loaded(key) then
      radiant.events.listen(radiant, key .. ':server:required_loaded', fortuna_romanorum, function()
        radiant.log.write_('fortuna_romanorum', 0, 'Fortuna Romanorum server monkey-patching after ' .. key)
        fortuna_romanorum.monkey_patching(value.enabled)
      end)
    else
      radiant.log.write_('fortuna_romanorum', 0, 'Fortuna Romanorum server did not detect ' .. key)
      for from, into in pairs(value.disabled) do
        monkey_patches[from] = into
      end
    end
  end
  radiant.events.listen(radiant, 'radiant:required_loaded', fortuna_romanorum, fortuna_romanorum._on_required_loaded)
end

function fortuna_romanorum.monkey_patching(patches)
  for from, into in pairs(patches) do
    local monkey_see = require('monkey_patches.' .. from)
    local monkey_do = radiant.mods.require(into)
    radiant.log.write_('fortuna_romanorum', 0, 'Fortuna Romanorum server monkey-patching sources \'' .. from .. '\' => \'' .. into .. '\'')
    if monkey_see.MERGE_PATCH_INTO_TABLE then
      -- use merge_into_table to also mixin other values, not just functions
      radiant.util.merge_into_table(monkey_do, monkey_see)
    else
      radiant.mixin(monkey_do, monkey_see)
    end
  end
end

function fortuna_romanorum.is_mod_loaded(namespace)
  for _, mod in ipairs(radiant.resources.get_mod_list()) do
    if mod == namespace then
      return true
    end
  end
  return false
end

function fortuna_romanorum._on_init()
  radiant.log.write_('fortuna_romanorum', 0, 'Fortuna Romanorum (v1.0.8) server initialized')
  for _, mod_name in ipairs(required_mods) do
    if not fortuna_romanorum.is_mod_loaded(mod_name) then
      error('Fortuna Romanorum (fortuna_romanorum) mod requires the following mod which was not loaded: ' .. mod_name)
    end
  end
  fortuna_romanorum.setup_patching()
end

function fortuna_romanorum._on_required_loaded()
  fortuna_romanorum.monkey_patching(init_patches)
  radiant.events.trigger_async(radiant, 'fortuna_romanorum:server:required_loaded')
end

function fortuna_romanorum:_on_biome_set(e)
  if e.biome_uri ~= "fortuna_romanorum:biome:coast" then
    return
  end

  local coast_init_patches = coast_patches
  for k,_ in pairs(init_patches) do
    coast_init_patches[k] = nil
  end

  fortuna_romanorum.monkey_patching(coast_init_patches)
end

function fortuna_romanorum._on_game_loaded()
  local biome_uri = stonehearth.world_generation:get_biome_alias()
  if biome_uri ~= "fortuna_romanorum:biome:coast" then
    return
  end
  radiant.log.write_('fortuna_romanorum', 0, 'Fortuna Romanorum server loading game in fortuna_romanorum:biome:coast')
  fortuna_romanorum.monkey_patching(coast_patches)
  stonehearth.world_generation:_setup_biome_data(biome_uri)
end

radiant.events.listen_once(fortuna_romanorum, 'radiant:init', fortuna_romanorum, fortuna_romanorum._on_init)
--radiant.events.listen_once(radiant, 'radiant:services:init', fortuna_romanorum, fortuna_romanorum._on_services_init)
radiant.events.listen_once(radiant, 'stonehearth:biome_set', fortuna_romanorum, fortuna_romanorum._on_biome_set)
radiant.events.listen_once(radiant, 'radiant:game_loaded', fortuna_romanorum, fortuna_romanorum._on_game_loaded)

return fortuna_romanorum
