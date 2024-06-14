-- local Biome = require 'stonehearth.services.server.world_generation.biome'
local Array2D = require 'stonehearth.services.server.world_generation.array_2D'
local SimplexNoise = require 'stonehearth.lib.math.simplex_noise'
local FilterFns = require 'stonehearth.services.server.world_generation.filter.filter_fns'
-- local ValleyShapes = require 'stonehearth.services.server.world_generation.valley_shapes'
-- local Timer = require 'stonehearth.services.server.world_generation.timer'
local log = radiant.log.create_logger('world_generation')

-- local MicroMapGenerator = require 'stonehearth.services.server.world_generation.micro_map_generator'
local CustomMicroMapGenerator = class()

function CustomMicroMapGenerator:generate_micro_map(size_x, size_y)
   local micro_map, width, height

   -- create the noise map
   micro_map = self:generate_noise_map(size_x, size_y)

   --stylistic interpolating with tile centroids based on distance to centroid, creates chunkiness on the macroscale
   --self:_blockify(micro_map, size_x, size_y)

   self:_match_lowest_percentile(micro_map)
   self:_accentuate_highest_terrain(micro_map)
   -- quantize it
   self:_quantize(micro_map)
   -- postprocess it
   self:_postprocess(micro_map)

   local elevation_map = self:_convert_to_elevation_map(micro_map)

   return micro_map, elevation_map
end

-- given a surface micro map, generate the underground micro map that indicates rock elevations
function CustomMicroMapGenerator:generate_underground_micro_map(surface_micro_map)
   local highest_terrain_info = self._terrain_info[self._biome._terrain_types[#self._biome._terrain_types]]
   local highest_terrain_base_height = highest_terrain_info.height_base
   local highest_terrain_step_size = highest_terrain_info.step_size
   local rock_line = highest_terrain_step_size
   local width, height = surface_micro_map:get_dimensions()
   local size = width*height
   local unfiltered_map = Array2D(width, height)
   local underground_micro_map = Array2D(width, height)

   -- seed the map using the above ground mountains
   for i=1, size do
      local surface_elevation = surface_micro_map[i]
      local value

      if surface_elevation > highest_terrain_base_height then
         value = surface_elevation
      else
         value = math.max(surface_elevation - highest_terrain_step_size*2, rock_line)
      end

      unfiltered_map[i] = value
   end

   -- filter the map to generate the underground height map
   FilterFns.filter_2D_0125(underground_micro_map, unfiltered_map, width, height, 10)

   local quantizer = self._biome:get_mountains_quantizer()

   -- quantize the height map
   for i=1, size do
      local surface_elevation = surface_micro_map[i]
      local rock_elevation

      if surface_elevation > highest_terrain_base_height then
         -- if the mountain breaks the surface just use its height
         rock_elevation = surface_elevation
      else
         -- quantize the filtered value
         rock_elevation = quantizer:quantize(underground_micro_map[i])

         -- make sure the sides of the rock faces stay beneath the surface
         -- e.g. we don't want a drop in an adjacent foothills block to expose the rock
         if rock_elevation > surface_elevation - highest_terrain_step_size then
            rock_elevation = rock_elevation - highest_terrain_step_size
         end

         -- make sure we have a layer of rock beneath everything
         if rock_elevation <= 0 then
            rock_elevation = rock_line
         end
      end

      underground_micro_map[i] = rock_elevation
   end

   local underground_elevation_map = self:_convert_to_elevation_map(underground_micro_map)

   return underground_micro_map, underground_elevation_map
end

function CustomMicroMapGenerator:generate_noise_map(size_x, size_y)
   local function get_highest_terrain_info(biome_instance)
      return biome_instance._terrain_info[biome_instance._terrain_types[#(biome_instance._terrain_types)]]
   end

   local highest_terrain_info = get_highest_terrain_info(self._biome)
   local macro_blocks_per_tile = self._macro_blocks_per_tile
   -- +1 for half macro_block margin on each edge
   local width = size_x * macro_blocks_per_tile + 1
   local height = size_y * macro_blocks_per_tile + 1
   local noise_map = Array2D(width, height)

   local fn = function (x,y)
      local noise_config = self._terrain_info.noise_map_settings
      local mean = highest_terrain_info.height_base
      local range = (highest_terrain_info.height_max - mean)*2
      local height = SimplexNoise.proportional_simplex_noise(noise_config.octaves,noise_config.persistence_ratio,noise_config.bandlimit, mean,range, noise_config.aspect_ratio, self._seed,x,y)
      return height
   end
   noise_map:fill(fn)
   return noise_map
end

--pull up the highest_terrain with a smooth exponential map,
-- so the maximum height from generated noise tries to match the intended maximum height
function CustomMicroMapGenerator:_accentuate_highest_terrain(micro_map)
   local function get_highest_terrain_info(biome_instance)
      return biome_instance._terrain_info[biome_instance._terrain_types[#(biome_instance._terrain_types)]]
   end

   local highest_terrain_info = get_highest_terrain_info(self._biome)
   local highest_terrain_base = highest_terrain_info.height_base
   local raw_highest_terrain_range = self:get_percentile_altitude(99, micro_map) - highest_terrain_base
   local highest_terrain_range = (highest_terrain_info.height_max - 0.5*highest_terrain_info.step_size - highest_terrain_base)
   --pull down the accentuation to eliminate overly steep highest_terrain
   raw_highest_terrain_range = 0.25*raw_highest_terrain_range+0.75*highest_terrain_range
   local exponential = math.log(highest_terrain_range) / math.log(raw_highest_terrain_range)
   local accentuation_fn = function(height)
      local result = height
      if height > highest_terrain_base then
         result = highest_terrain_base  + ((height - highest_terrain_base))^exponential
      end
      return result
   end
   micro_map:process(accentuation_fn)
end

-- NEW FUNCTION!
--offsets the height map so that the user specified amount of lowest/lowest+1 layer is reached
function CustomMicroMapGenerator:_match_lowest_percentile(micro_map)
   local percentile = self._terrain_info.custom_parameters and self._terrain_info.custom_parameters.lowest_percentage or self._terrain_info.plains_percentage
   local max = self._terrain_info.custom_parameters and self._terrain_info.custom_parameters.percentile_stretch_top or self._terrain_info.foothills.height_max
   if type(max) == 'string' then
      max = self._terrain_info[max].height_max
   end
   if percentile == nil then return end
   local altitude_difference = self:get_percentile_altitude(percentile, micro_map) - max
   log:info('altitude skew(%.2f)', altitude_difference)
   micro_map:process(
      function (value)
         return value - altitude_difference
      end
   )
end

function CustomMicroMapGenerator:_quantize(micro_map)
   local quantizer = self._biome:get_quantizer()
   local quantizer_max_height = self._terrain_info.custom_parameters and self._terrain_info.custom_parameters.quantizer_top or self._terrain_info[self._biome._terrain_types[1]].height_max
   if type(quantizer_max_height) == 'string' then
      quantizer_max_height = self._terrain_info[quantizer_max_height].height_max
   end

   micro_map:process(
      function (value)
         -- don't quantize below quantizer_max_height
         -- we have special detailing code for that
         -- could also use a different quantizer for this
         -- currently the same quantizer as the TerrainGenerator
         if value <= quantizer_max_height then
            return quantizer_max_height
         end
         return quantizer:quantize(value)
      end
   )
end

-- edge values may not change values! they are shared with the adjacent tile
function CustomMicroMapGenerator:_postprocess(micro_map)
   if self._terrain_info.custom_parameters and self._terrain_info.custom_parameters.micro_map_postprocessing then
      -- Sorting is necessary because ipairs() keeps the order while pairs() does not
      local filters = {}
      for key, value in pairs(self._terrain_info.custom_parameters.micro_map_postprocessing) do
         filters[tonumber(key)] = value
      end
      for _, value in ipairs(filters) do
         if value.method == 'remove_juts' then
            self:_remove_juts(micro_map)
         elseif value.method == 'fill_holes' then
            self:_fill_holes(micro_map)
         elseif value.method == 'grow_peaks' then
            self:_grow_peaks(micro_map)
         elseif value.method == 'remove_diagonals' then
            self:_remove_diagonals(micro_map, value.iterations)
         elseif value.method == 'force_ziggurat' then
            self:_force_ziggurat(micro_map, value.include_diagonal)
         elseif value.method == 'overflow_lower' then
            self:_overflow_lower(micro_map, value.height_threshold, value.iterations, value.include_diagonal, value.new_height)
         elseif value.method == 'fill_diagonals' then
            self:_fill_diagonals(micro_map, value.mode, value.iterations)
         elseif value.method == 'remove_loners' then
            self:_remove_loners(micro_map, value.mode)
         end
      end
   else
      self:_remove_juts(micro_map)
      self:_fill_holes(micro_map)
      self:_grow_peaks(micro_map)
   -- do this last, otherwise remove pointies will change the shapes
   -- self:_add_plains_valleys(micro_map)
   end
end
-- NEW FUNCTION!
function CustomMicroMapGenerator:_force_ziggurat(micro_map, include_diagonal)
   local temp = {}
   local step_heights = {}
   for id = 1, micro_map.width*micro_map.height do
      if (not temp[micro_map[id]]) then
          table.insert(step_heights,micro_map[id])
          temp[micro_map[id]] = true
      end
   end
   if #step_heights > 2 then
      table.sort(step_heights, function(a,b) return a > b end)
      for step = 1, (#step_heights-2) do
         self:_surround_lower(micro_map, step_heights[step], 1, include_diagonal, step_heights[step+1])
      end
   end
end
-- NEW FUNCTION!
function CustomMicroMapGenerator:_surround_lower(micro_map, height_threshold, iterations, include_diagonal, new_height)
   new_height = new_height or height_threshold
   for iter = 1,iterations do
      for j=2, micro_map.height-1 do
         for i=2, micro_map.width-1 do
            if micro_map:get(i,j) >= height_threshold then
               micro_map:perform_on_each_neighbor(i,j, include_diagonal, nil, function(a,b,value)
                  if value and value < new_height then
                     micro_map:set(a,b, new_height)
                  end
               end)
            end
         end
      end
   end
end
-- NEW FUNCTION!
function CustomMicroMapGenerator:_overflow_lower(micro_map, height_threshold, iterations, include_diagonal, new_height)
   new_height = new_height or height_threshold
   for iter = 1,iterations do
      local old_micro_map = micro_map:clone()
      for j=2, micro_map.height-1 do
         for i=2, micro_map.width-1 do
            if micro_map:get(i,j) < height_threshold then
               local result = false
               old_micro_map:each_neighbor(i,j, include_diagonal, function(value)
                  if value >= height_threshold then
                     result = true
                     return true
                  end
               end)
               if result then
                  micro_map:set(i,j,new_height)
               end
            end
         end
      end
   end
end
-- NEW FUNCTION!
function CustomMicroMapGenerator:_fill_diagonals(micro_map, mode, iterations)
   if mode == 'descend' then
      for times = 1,iterations do
         for j=1, micro_map.height-1 do
            for i=1, micro_map.width-1 do
               local NE = micro_map:get(i,j+1)
               local NW = micro_map:get(i,j)
               local SW = micro_map:get(i+1,j)
               local SE = micro_map:get(i+1,j+1)
               if NE == SW then
                  if NW < NE and SE > NE then
                     micro_map:set(i+1,j+1,NE)
                  elseif NW > NE and SE < NE then
                     micro_map:set(i,j,NE)
                  end
               elseif NW == SE then
                  if NE < NW and SW > NW then
                     micro_map:set(i+1,j, NW)
                  elseif NE > NW and SW < NW then
                     micro_map:set(i,j+1, NW)
                  end
               end
            end
         end
      end
   elseif mode == 'ascend' then
      for times = 1,iterations do
         for j=1, micro_map.height-1 do
            for i=1, micro_map.width-1 do
               local NE = micro_map:get(i,j+1)
               local NW = micro_map:get(i,j)
               local SW = micro_map:get(i+1,j)
               local SE = micro_map:get(i+1,j+1)
               if NE == SW then
                  if NW < NE and SE > NE then
                     micro_map:set(i,j,NE)
                  elseif NW > NE and SE < NE then
                     micro_map:set(i+1,j+1,NE)
                  end
               elseif NW == SE then
                  if NE < NW and SW > NW then
                     micro_map:set(i,j+1, NW)
                  elseif NE > NW and SW < NW then
                     micro_map:set(i+1,j, NW)
                  end
               end
            end
         end
      end
   end
end
-- NEW FUNCTION!
function CustomMicroMapGenerator:_remove_loners(micro_map, mode)
   if mode == 'min' then
      for j=2, micro_map.height-1 do
         for i=2, micro_map.width-1 do
            local C = micro_map:get(i,j)
            local E = micro_map:get(i+1,j)
            local N = micro_map:get(i,j+1)
            local W = micro_map:get(i-1,j)
            local S = micro_map:get(i,j-1)
            if not (C == E or C == N or C == W or C == S) then
               micro_map:set(i,j,math.min(W,N,E,S))
            end
         end
      end
   elseif mode == 'max' then
      for j=2, micro_map.height-1 do
         for i=2, micro_map.width-1 do
            local C = micro_map:get(i,j)
            local E = micro_map:get(i+1,j)
            local N = micro_map:get(i,j+1)
            local W = micro_map:get(i-1,j)
            local S = micro_map:get(i,j-1)
            if not (C == E or C == N or C == W or C == S) then
               micro_map:set(i,j,math.max(W,N,E,S))
            end
         end
      end
   elseif mode == 'random' then
      for j=2, micro_map.height-1 do
         for i=2, micro_map.width-1 do
            local C = micro_map:get(i,j)
            local E = micro_map:get(i+1,j)
            local N = micro_map:get(i,j+1)
            local W = micro_map:get(i-1,j)
            local S = micro_map:get(i,j-1)
            if not (C == E or C == N or C == W or C == S) then
               local pool = {W,N,E,S}
               micro_map:set(i,j,pool[math.random(4)])
            end
         end
      end
   end
end

return CustomMicroMapGenerator
