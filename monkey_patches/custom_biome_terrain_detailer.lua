-- local Biome = require 'stonehearth.services.server.world_generation.biome'
-- local Array2D = require 'stonehearth.services.server.world_generation.array_2D'
-- local SimplexNoise = require 'stonehearth.lib.math.simplex_noise'
-- local FilterFns = require 'stonehearth.services.server.world_generation.filter.filter_fns'
-- local InverseGaussianRandom = require 'stonehearth.lib.math.inverse_gaussian_random'

-- local TerrainDetailer = require 'stonehearth.services.server.world_generation.terrain_detailer'
local CustomTerrainDetailer = class()

-- local log = radiant.log.create_logger('world_generation.detailer')

-- NEW FUNCTION!
function CustomTerrainDetailer:_is_regular_detailer(terrain_type)
local config = self._detail_info[terrain_type]
   if config then
      local depth_config = config.depth_function
      local height_config = config.height_function
      if depth_config and height_config and self._terrain_info[terrain_type].step_size then
         if depth_config.octaves and depth_config.persistence_ratio and depth_config.amplitude and depth_config.layer_thickness and depth_config.layer_count and depth_config.unit_length and height_config.octaves and height_config.persistence_ratio and height_config.amplitude and height_config.layer_thickness and height_config.unit_length then
            return true
         end
      end
   end
   return false
end
-- NEW FUNCTION!
function CustomTerrainDetailer:_is_plains_detailer(terrain_type)
local config = self._detail_info[terrain_type]
   if config then
      local depth_config = config.depth_function
      local height_config = config.height_function
      if depth_config and height_config and self._terrain_info[terrain_type].step_size then
         if depth_config.layer_thickness and depth_config.layer_count and depth_config.unit_length and height_config.layer_thickness and height_config.unit_length then
            if depth_config.octaves and depth_config.persistence_ratio and depth_config.amplitude and height_config.octaves and height_config.persistence_ratio and height_config.amplitude then
               return false
            end
            return true
         end
      end
   end
   return false
end

function CustomTerrainDetailer:_initialize_function_table()
   local functions = {}
   for _, terrain_type in ipairs(self._biome._terrain_types) do
      if self:_is_regular_detailer(terrain_type) then
          functions[terrain_type] = self:_initialize_detailer(terrain_type)
      elseif self:_is_plains_detailer(terrain_type) then
          functions[terrain_type] = self:_initialize_plains_detailer()
      end
   end
   self._function_table = functions
end

function CustomTerrainDetailer:_detail_layer(layer, tile_map, old_map, edge_map, depth_map, traversed)
   local width = tile_map.width
   local height = tile_map.height
   local detail_info = self._detail_info

   for j=1, height do
      for i=1, width do
         --check if edge has at least a depth of "layer"
         if depth_map:get(i, j) >= layer then
            local normals = edge_map:get(i, j)
            if #normals == 1 then
               --initialization
               local normal = normals[1]
               local old_altitude = old_map:get(i,j)
               local terrain_type = self._biome:get_terrain_type(old_altitude)
               local step_size = self._terrain_info[terrain_type].step_size
               local base = old_altitude - step_size
               local depth_layer_thickness = detail_info[terrain_type].depth_function.layer_thickness
               local height_layer_thickness = detail_info[terrain_type].height_function.layer_thickness
               --base is the base of this protrusion layer
               local i_base = i + (layer-1)*depth_layer_thickness*normal.x
               local j_base = j + (layer-1)*depth_layer_thickness*normal.y
               --set height of protrusion layer
               local offset = self:_edge_border_offset(tile_map, height_layer_thickness, i_base, j_base, normal.x, normal.y)
               local inset_function = self._function_table[terrain_type].inset_function
               local altitude = tile_map:get(i_base,j_base) - height_layer_thickness*(inset_function(i_base,j_base)) - offset
               --snap so that there are no detailing chunks of offset one from base
               altitude = self:_snap_altitude(altitude, base, step_size)
               --set protrusion layer
               for index = 1, depth_layer_thickness do
                  local i_protrude = i_base + index*normal.x
                  local j_protrude = j_base + index*normal.y
                  self:_set_protrusion(altitude, i_protrude, j_protrude, tile_map, traversed)
               end
            end
         end
      end
   end
   -- additional pass to remove redundant diagonals
   for j=1, height-1 do
      for i=1, width-1 do
         local NE = tile_map:get(i,j+1)
         local NW = tile_map:get(i,j)
         local SW = tile_map:get(i+1,j)
         local SE = tile_map:get(i+1,j+1)
         if (NE == SW) and (NW == SE) then
            if NE > NW then
               tile_map:set(i,j+1,NW)
               tile_map:set(i+1,j,NW)
            elseif NE < NW then
               tile_map:set(i,j,NE)
               tile_map:set(i+1,j+1,NE)
            end
         end
      end
   end
end

function CustomTerrainDetailer:_get_normal_permutes(normals, terrain_type)
   local permutes = {}

   if self:_is_plains_detailer(terrain_type) and #normals > 1 then
      -- don't detail convex corners on foothills and mountains
      -- too difficult and looks bad
      return permutes
   end

   assert(#normals <= 2)
   local sum

   if #normals == 2 then
      sum = { x = 0, y = 0 }
   end

   for _, normal in ipairs(normals) do
      table.insert(permutes, normal)
      if #normals == 2 then
         sum.x = sum.x + normal.x
         sum.y = sum.y + normal.y
      end
   end

   if #normals == 2 then
      table.insert(permutes, sum)
   end

   return permutes
end

return CustomTerrainDetailer
