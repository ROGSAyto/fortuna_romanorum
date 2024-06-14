-- local Biome = require 'stonehearth.services.server.world_generation.biome'
-- local NonUniformQuantizer = require 'stonehearth.lib.math.non_uniform_quantizer'
-- local WeightedSet = require 'stonehearth.lib.algorithms.weighted_set'
local Array2D = require 'stonehearth.services.server.world_generation.array_2D'
local SimplexNoise = require 'stonehearth.lib.math.simplex_noise'
local FilterFns = require 'stonehearth.services.server.world_generation.filter.filter_fns'
local PerturbationGrid = require 'stonehearth.services.server.world_generation.perturbation_grid'
-- local Timer = require 'stonehearth.services.server.world_generation.timer'
local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local Region3 = _radiant.csg.Region3
--clocal log = radiant.log.create_logger('world_generation')

-- local tree_tag = ':trees:'
local generic_vegetation_name = "vegetation"

-- TO DO: unhardcode water layers
-- local water_shallow = 'water_1'
-- local water_deep = 'water_2'

local CustomLandscaper = class()

function CustomLandscaper:__init(biome, rng, seed)
   self._biome = biome
   self._tile_width = self._biome:get_tile_size()
   self._tile_height = self._biome:get_tile_size()
   self._feature_size = self._biome:get_feature_block_size()
   self._landscape_info = self._biome:get_landscape_info()
   self._rng = rng
   self._seed = seed

   self._noise_map_buffer = nil
   self._density_map_buffer = nil

   self._perturbation_grid = PerturbationGrid(self._tile_width, self._tile_height, self._feature_size, self._rng)

   self._water_table = {}
   self._water_radius = {}
   if self._landscape_info.water.custom_levels then
      for key, value in pairs(self._landscape_info.water.custom_levels) do
         self._water_table['water_' .. value.order] = self._landscape_info.water.depth[key] or 5
         self._water_radius['water_' .. value.order] = value.radius or 1
      end
   else
      self._water_table = {
         water_1 = self._landscape_info.water.depth.shallow,
         water_2 = self._landscape_info.water.depth.deep
      }
      self._water_radius = {
         water_1 = 1,
         water_2 = 1
      }
   end

   self:_parse_landscape_info()

   self._extra_map_options_on = false
   if stonehearth.game_creation.get_extra_map_options then
      local custom_map_options = stonehearth.game_creation:get_extra_map_options()

      self._world_size = custom_map_options.world_size
      self._lakes = custom_map_options.lakes
      self._rivers = custom_map_options.rivers
      self._sky_lands = custom_map_options.modes.sky_lands
      self._waterworld = custom_map_options.modes.waterworld
      self._extra_map_options_on = true
   end
end

function CustomLandscaper:mark_water_bodies(elevation_map, feature_map)
   local rng = self._rng
   local biome = self._biome
   local config = self._landscape_info.water.noise_map_settings
   local modifier_map, density_map = self:_get_filter_buffers(feature_map.width, feature_map.height)
   --fill modifier map to push water bodies away from terrain type boundaries
   local modifier_fn = function (i,j)
      if self:_is_flat(elevation_map, i, j, 1) then
         return 0
      else
         return -1*config.range
      end
   end
   --use density map as buffer for smoothing filter
   density_map:fill(modifier_fn)
   FilterFns.filter_2D_0125(modifier_map, density_map, modifier_map.width, modifier_map.height, 10)
   --mark water bodies on feature map using density map and simplex noise
   local old_feature_map = Array2D(feature_map.width, feature_map.height)
   local terrain_types_to_ring = {}
   if config.boolean_layers then
      for key, value in pairs(config.boolean_layers) do
         if (type(value) == 'number') and (value ~=0) then
            terrain_types_to_ring[key] = value
         end
      end
   end
   for j=1, feature_map.height do
      for i=1, feature_map.width do
         local occupied = feature_map:get(i, j) ~= nil
         if not occupied then
            local elevation = elevation_map:get(i, j)
            local terrain_type = biome:get_terrain_type(elevation)
            local value = 0
            if config.boolean_layers and config.boolean_layers[terrain_type] then
               if terrain_types_to_ring[terrain_type] or (config.boolean_layers[terrain_type] == 'dry') then
                  value = -1
               elseif config.boolean_layers[terrain_type] == 'flooded' then
                  value = 1
               end
            else
               if (self._extra_map_options_on and self._lakes) or not self._extra_map_options_on then
                  value = SimplexNoise.proportional_simplex_noise(config.octaves,config.persistence_ratio, config.bandlimit,config.mean[terrain_type],config.range,config.aspect_ratio, self._seed,i,j)
                  value = value + modifier_map:get(i,j)
               else
                  value = -1
               end
            end
            if value > 0 then
               local old_value = feature_map:get(i, j)
               old_feature_map:set(i, j, old_value)
               feature_map:set(i, j, 'water_1')
            end
         end
      end
   end
   self:_remove_juts(feature_map)
   self:_remove_ponds(feature_map, old_feature_map)
   self:_fix_tile_aligned_water_boundaries(feature_map, old_feature_map)
   for key, iter_num in pairs(terrain_types_to_ring) do
      self:_add_feature_ring_around_terrain('water_1', key, feature_map, elevation_map, iter_num, true)
   end
   self:_add_deep_water(feature_map)
end

-- NEW FUNCTION!
function CustomLandscaper:_add_feature_ring_around_terrain(feature_name, terrain_type, feature_map, elevation_map, iter_num, include_diagonal)
   local mode = 'outer'
   if iter_num < 0 then
      mode = 'inner'
      iter_num = -iter_num
   end
   local temp_feature_map = feature_map:clone()
   -- Significantly faster than calling the biome function every time
   local height_base = self._biome._terrain_info[terrain_type].height_base + 1
   local height_max = self._biome._terrain_info[terrain_type].height_max

   for j=1, temp_feature_map.height do
      for i=1, temp_feature_map.width do
         local value = elevation_map:get(i,j)
         if  value >= height_base and value <= height_max then
            temp_feature_map:set(i, j, 'clear_me')
         end
      end
   end

   for j=1, temp_feature_map.height do
      for i=1, temp_feature_map.width do
         local result = true
         elevation_map:each_neighbor_or_oob(i,j, include_diagonal, height_base, function(value)
            if value < height_base or value > height_max then
               result = false
               return true
            end
         end)
         if result then
            temp_feature_map:set(i, j, 'mark_me')
         end
      end
   end

   for iter =1,(iter_num-1) do
      for j=1, temp_feature_map.height do
         for i=1, temp_feature_map.width do
            if temp_feature_map:get(i,j) == 'mark_me' then
               local result = false
               temp_feature_map:each_neighbor_or_oob(i,j, include_diagonal, 'mark_me', function(value)
                     if not (value == 'mark_me' or value == 'unmark_me') then
                        result = true
                        return true
                     end
                  end)
               if result then
                  temp_feature_map:set(i, j, 'unmark_me')
               end
            end
         end
      end
      for j=1, temp_feature_map.height do
         for i=1, temp_feature_map.width do
            if temp_feature_map:get(i,j) == 'unmark_me' then
               temp_feature_map:set(i, j, 'clear_me')
            end
         end
      end
   end

   local positive = (mode == 'inner') and 'clear_me' or 'mark_me'

   for j=1, temp_feature_map.height do
      for i=1, temp_feature_map.width do
         local feature = temp_feature_map:get(i,j)
         if feature == positive then
            feature_map:set(i, j, feature_name)
         end
      end
   end

end

-- NEW FUNCTION!
function CustomLandscaper:_add_feature_ring_around_feature(feature_name, feature_to_surround, feature_map, iter_num, include_diagonal)
   local mode = 'outer'
   if iter_num < 0 then
      mode = 'inner'
      iter_num = -iter_num
   end
   local temp_feature_map = feature_map:clone()

   for j=1, feature_map.height do
      for i=1, feature_map.width do
         if temp_feature_map:get(i,j) == feature_to_surround then
            temp_feature_map:set(i, j, 'mark_me')
         end
      end
   end

   for iter =1,iter_num do
      for j=1, temp_feature_map.height do
         for i=1, temp_feature_map.width do
            if temp_feature_map:get(i,j) == 'mark_me' then
               local result = false
               temp_feature_map:each_neighbor_or_oob(i,j, include_diagonal, 'mark_me', function(value)
                     if not (value == 'mark_me' or value == 'unmark_me') then
                        result = true
                        return true
                     end
                  end)
               if result then
                  temp_feature_map:set(i, j, 'unmark_me')
               end
            end
         end
      end
      for j=1, temp_feature_map.height do
         for i=1, temp_feature_map.width do
            if temp_feature_map:get(i,j) == 'unmark_me' then
               temp_feature_map:set(i, j, 'clear_me')
            end
         end
      end
   end

   local positive = (mode == 'inner') and 'clear_me' or 'mark_me'

   for j=1, temp_feature_map.height do
      for i=1, temp_feature_map.width do
         local feature = temp_feature_map:get(i,j)
         if feature == positive then
            feature_map:set(i, j, feature_name)
         end
      end
   end

end

function CustomLandscaper:_add_deep_water(feature_map, include_diagonal)
   if include_diagonal == nil then include_diagonal = true end
   local waters = {}
   for key, value in pairs(self._water_radius) do
      waters[tonumber(string.sub(key, 7, string.len(key)))] = value
   end
   if #waters < 2 then
      return
   end
   for i = 1,(#waters - 1) do
      self:_add_feature_ring_around_feature('water_' .. (i+1), 'water_' .. i, feature_map, waters[i], include_diagonal)
   end
end

function CustomLandscaper:place_water_bodies(tile_region, elevation_map, feature_map, tile_offset_x, tile_offset_y)
   local water_region = Region3()

   feature_map:visit(function(value, i, j)
         if not self:is_water_feature(value) then
            return
         end

         local depth = self._water_table[value]
         local x, y, w, h = self._perturbation_grid:get_cell_bounds(i, j)
         -- use the center of the cell to get the elevation because the edges may have been detailed
         local lake_top = elevation_map:get(i, j)
         local lake_bottom = math.max(1, lake_top - depth)

         local world_x, world_z = self:_to_world_coordinates(x, y, tile_offset_x, tile_offset_y)

         local free_volume = Region3()
         free_volume:add_cube(Cube3(
                  Point3(world_x, lake_top, world_z),
                  Point3(world_x + w, lake_top+1, world_z + h)
               ))
         free_volume:subtract_region(tile_region)

         for cube in free_volume:each_cube() do
            cube.min.y = lake_bottom
            cube.max.y = lake_top
            tile_region:subtract_cube(cube)
            water_region:add_cube(cube)
         end

      end)

   water_region:optimize('place water bodies')

   return water_region
end

function CustomLandscaper:is_water_feature(feature_name)
   return self._water_table[feature_name] ~= nil
end

function CustomLandscaper:mark_trees(elevation_map, feature_map)
   local rng = self._rng
   local biome = self._biome

   local noise_map, density_map = self:_get_filter_buffers(feature_map.width, feature_map.height)
   local tree_name, tree_type, tree_size, occupied, value, elevation, tree_types, tree_density, noise_variant
   --generate initial gaussian noise for density map
   local noise_fn = function(i, j)
      local noise_mean_offset = self._landscape_info.trees.noise_map_parameters.mean_offset
      elevation = elevation_map:get(i, j)
      noise_variant = self:_get_variant(self._tree_data.noise_map_parameters, elevation)
      local mean = noise_variant.mean
      local std_dev = noise_variant.std_dev

      local feature = feature_map:get(i,j)
      if self:is_water_feature(feature) then
         mean = mean + noise_mean_offset.water
      end
      if not self:_is_flat(elevation_map, i, j, 1) then
         mean = mean + noise_mean_offset.boundary
      end
      --note this is not the terrain boundary in the json file, but the edge of the noise map/feature map.
      if noise_map:is_boundary(i, j) then
         mean = mean - 20
      end
      return rng:get_gaussian(mean, std_dev)
   end
   --fill map and smooth out boundaries
   noise_map:fill(noise_fn)
   FilterFns.filter_2D_0125(density_map, noise_map, noise_map.width, noise_map.height, 10)

   --determine trees based on density function and terrain
   for j=1, density_map.height do
      for i=1, density_map.width do
         occupied = feature_map:get(i, j) ~= nil

         if not occupied then
            value = density_map:get(i, j)
            if value > 0 then
               elevation = elevation_map:get(i, j)
               tree_types = self:_get_variant(self._tree_data.types, elevation)
               noise_variant = self:_get_variant(self._tree_data.noise_map_parameters, elevation)

               tree_type = tree_types:choose_random()
               tree_size = self:_get_tree_size(tree_type, value)
               tree_name = get_tree_name(tree_type, tree_size)
               tree_density = noise_variant.density
               --determine density cutoff
               --set trees based on density cutoff
               if rng:get_real(0, 1) < tree_density then
                  feature_map:set(i, j, tree_name)
               else
                  -- the higher tree densities are used to thin the trees so that they are not visually too dense
                  -- we plug the holes from this 'thinning' so that tree-loving flora don't always fill the holes
                  if tree_density > 0.5 then
                     feature_map:set(i, j, generic_vegetation_name)
                  end
               end
            end
         end
      end
   end
end
--gets variant based on terrain step
function CustomLandscaper:_get_variant(variant_maps, elevation)
   local terrain_type, step = self._biome:get_terrain_type_and_step(elevation)
   local variant_map = variant_maps[terrain_type]
   local dependent_step = variant_map.step_map[step]
   local variant = variant_map.step_variants[dependent_step]
   return variant
end

-- NEW FUNCTION!
function CustomLandscaper:_get_habitat_mappings()
   local terrain_info = self._biome:get_terrain_info()
   local before_features = {mountains = 'mountains'}
   local after_features = {plains = 'plains', foothills = 'foothills'}
   if terrain_info.custom_parameters and terrain_info.custom_parameters.habitat_mappings then
      before_features = terrain_info.custom_parameters.habitat_mappings.before_features or {}
      after_features = terrain_info.custom_parameters.habitat_mappings.after_features or {}
   end
   return before_features, after_features
end

return CustomLandscaper
