praetorianClass = class()
local CombatJob = require 'stonehearth.jobs.combat_job'
radiant.mixin(praetorianClass, CombatJob)
return praetorianClass