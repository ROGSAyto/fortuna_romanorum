-- local Array2D = require 'stonehearth.services.server.world_generation.array_2D'
local CustomArray2D = class()

function CustomArray2D:each_neighbor_or_oob(x, y, include_diagonal, result_if_oob, fn)
   local width = self.width
   local offset = (y-1)*width + x -- faster than calling get_offset()
   local neighbors = {}

   local count = 4
   if self:in_bounds(x-1,y) then neighbors[1] = self[offset-1] else neighbors[1] = result_if_oob end
   if self:in_bounds(x+1,y) then neighbors[2] = self[offset+1] else neighbors[2] = result_if_oob end
   if self:in_bounds(x,y-1) then neighbors[3] = self[offset-width] else neighbors[3] = result_if_oob end
   if self:in_bounds(x,y+1) then neighbors[4] = self[offset+width] else neighbors[4] = result_if_oob end

   if include_diagonal then
      count = 8
      if self:in_bounds(x-1,y-1) then neighbors[5] = self[offset-1-width] else neighbors[5] = result_if_oob end
      if self:in_bounds(x+1,y-1) then neighbors[6] = self[offset+1-width] else neighbors[6] = result_if_oob end
      if self:in_bounds(x-1,y+1) then neighbors[7] = self[offset-1+width] else neighbors[7] = result_if_oob end
      if self:in_bounds(x+1,y+1) then neighbors[8] = self[offset+1+width] else neighbors[8] = result_if_oob end
   end

   -- don't use #neighbors since the values could be nil and we'll skip the callback
   for i = 1, count do
      local stop = fn(neighbors[i])
      if stop then
         return
      end
   end
end

function CustomArray2D:perform_on_each_neighbor(x, y, include_diagonal, result_if_oob, fn)
   local width = self.width
   local offset = (y-1)*width + x -- faster than calling get_offset()
   local neighbors = {}
   local i = {x-1,x+1,x,x,x-1,x+1,x-1,x+1}
   local j = {y,y,y-1,y+1,y-1,y-1,y+1,y+1}

   local count = 4
   if self:in_bounds(i[1],j[1]) then neighbors[1] = self[offset-1] else neighbors[1] = result_if_oob end
   if self:in_bounds(i[2],j[2]) then neighbors[2] = self[offset+1] else neighbors[2] = result_if_oob end
   if self:in_bounds(i[3],j[3]) then neighbors[3] = self[offset-width] else neighbors[3] = result_if_oob end
   if self:in_bounds(i[4],j[4]) then neighbors[4] = self[offset+width] else neighbors[4] = result_if_oob end

   if include_diagonal then
      count = 8
      if self:in_bounds(i[5],j[5]) then neighbors[5] = self[offset-1-width] else neighbors[5] = result_if_oob end
      if self:in_bounds(i[6],j[6]) then neighbors[6] = self[offset+1-width] else neighbors[6] = result_if_oob end
      if self:in_bounds(i[7],j[7]) then neighbors[7] = self[offset-1+width] else neighbors[7] = result_if_oob end
      if self:in_bounds(i[8],j[8]) then neighbors[8] = self[offset+1+width] else neighbors[8] = result_if_oob end
   end

   -- don't use #neighbors since the values could be nil and we'll skip the callback
   for element = 1, count do
      local stop = fn(i[element],j[element],neighbors[element])
      if stop then
         return
      end
   end
end

return CustomArray2D
