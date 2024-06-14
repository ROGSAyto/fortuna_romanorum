local SkullAmount = class()
local material1 = 'stockpile_trophy'
local material2 = 'bone'

function SkullAmount:start()
	local skull_amount = stonehearth.inventory:get_material_count('stockpile_trophy')
    if skull_amount > 4 then
        return true
    else
        return false
    end
end

return SkullAmount