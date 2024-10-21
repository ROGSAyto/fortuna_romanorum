fortuna_romanorum = {}

-- Liste der erforderlichen Mods
local required_mods = {
  "stonehearth",
  "rayyas_children",
  "northern_alliance",
  "stonehearth_ace",
  "lostems",
  "archipelago_biome"
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

function fortuna_romanorum.is_mod_loaded(namespace)
  for _, mod in ipairs(radiant.resources.get_mod_list()) do
    if mod == namespace then
      return true
    end
  end
  return false
end

function fortuna_romanorum._on_init()
  radiant.log.write_('fortuna_romanorum', 0, 'Fortuna Romanorum (v1.0.0) server initialized')
  for _, mod_name in ipairs(required_mods) do
    if not fortuna_romanorum.is_mod_loaded(mod_name) then
      error('Fortuna Romanorum (fortuna_romanorum) mod requires the following mod which was not loaded: ' .. mod_name)
    end
  end
  fortuna_romanorum.setup_patching()
end

--radiant.events.listen_once(fortuna_romanorum, 'radiant:init', fortuna_romanorum, fortuna_romanorum._on_init)
--radiant.events.listen_once(radiant, 'radiant:services:init', fortuna_romanorum, fortuna_romanorum._on_services_init)
--radiant.events.listen_once(radiant, 'stonehearth:biome_set', fortuna_romanorum, fortuna_romanorum._on_biome_set)
--radiant.events.listen_once(radiant, 'radiant:game_loaded', fortuna_romanorum, fortuna_romanorum._on_game_loaded)

return fortuna_romanorum
