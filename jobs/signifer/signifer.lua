SigniferClass = class()
local CombatJob = require 'stonehearth.jobs.combat_job'
radiant.mixin(SigniferClass, CombatJob)
return SigniferClass