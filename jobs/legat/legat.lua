legatClass = class()
local CombatJob = require 'stonehearth.jobs.combat_job'
radiant.mixin(legatClass, CombatJob)
return legatClass
