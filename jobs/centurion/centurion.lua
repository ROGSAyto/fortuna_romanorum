CenturionClass = class()
local CombatJob = require 'stonehearth.jobs.combat_job'
radiant.mixin(CenturionClass, CombatJob)
return CenturionClass