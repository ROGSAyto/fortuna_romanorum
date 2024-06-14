-- local Array2D = require 'stonehearth.services.server.world_generation.array_2D'
-- local Rect2 = _radiant.csg.Rect2
-- local Point2 = _radiant.csg.Point2
local Cube3 = _radiant.csg.Cube3
local Point3 = _radiant.csg.Point3
-- local Region2 = _radiant.csg.Region2
local Region3 = _radiant.csg.Region3
-- local HeightMapCPP = _radiant.csg.HeightMap

-- local HeightMapRenderer = require 'stonehearth.services.server.world_generation.height_map_renderer'
local CustomHeightMapRenderer = class()

function CustomHeightMapRenderer:__init(biome)
   self._biome = biome
   self._tile_size = self._biome:get_tile_size()
   self._terrain_component = radiant.terrain.get_terrain_component()
   self._block_types = radiant.terrain.get_block_types()

   -- rock layers
   local terrain_info = self._biome:get_terrain_info()
   local highest_info = terrain_info[self._biome._terrain_types[#self._biome._terrain_types]]
   local rock_layers = {}
   local terrain_tags = {}
   local block_types = self._block_types
   local num_rock_layers = 0
   for name, tag in pairs(block_types) do
      if name ~= 'bedrock' and radiant.terrain.get_block_kind_from_tag(tag) == 'rock' then
         num_rock_layers = num_rock_layers +1
      end
   end

   for n = 1,num_rock_layers do
      table.insert(terrain_tags, block_types['rock_layer_' .. n])
   end
   for i, tag in ipairs(terrain_tags) do
      rock_layers[i] = {
         terrain_tag = tag,
         max_height = highest_info.height_base + highest_info.step_size*i
      }
   end

   self._rock_layers = rock_layers
   self._num_rock_layers = #rock_layers

   -- add land function table
   self._add_land_functions = {
      plains = self._add_plains_to_region,
      foothills = self._add_foothills_to_region,
      mountains = self._add_mountains_to_region
   }

   -- custom specification handling
   self._terrain_type_uses_custom_function = {}
   if terrain_info.custom_types then
      for key, value in pairs(terrain_info.custom_types) do
         self._terrain_type_uses_custom_function[key] = true
      end
   end

   local bedrock_height = (terrain_info.custom_parameters and terrain_info.custom_parameters.bedrock_height) and terrain_info.custom_parameters.bedrock_height or 4
   self._custom_layer_definitions = {}
   if terrain_info.custom_layers then
      for key, value in pairs(terrain_info.custom_layers) do
         self._custom_layer_definitions[key] = {}
         if value.pattern then
            for n, entry in pairs(value.pattern) do
               self._custom_layer_definitions[key][tonumber(n)] = {
                  terrain_tag = block_types[entry.terrain_type],
                  layer_thickness = entry.thickness
               }
            end
            local bottom = value.height_base + bedrock_height
            for i = 1,#(self._custom_layer_definitions[key]) do
               bottom = bottom + self._custom_layer_definitions[key][i].layer_thickness
               self._custom_layer_definitions[key][i].max_height = bottom
            end
         elseif value.step_size then
            for i = 1,value.num_layers do
               self._custom_layer_definitions[key][i] = {
                  terrain_tag = block_types[key .. '_layer_' .. i],
                  layer_thickness = value.step_size,
                  max_height = value.height_base + bedrock_height + value.step_size*i
               }
            end
         end -- TO DO: accept an advanced layer pattern if step_size not provided
      end
   end

   self._show_tile_boundaries = radiant.util.get_config('show_tile_boundaries', false)
end

function CustomHeightMapRenderer:render_height_map_to_region(region3, height_map, underground_height_map)
   assert(height_map.width == self._tile_size)
   assert(height_map.height == self._tile_size)
   assert(underground_height_map.width == self._tile_size)
   assert(underground_height_map.height == self._tile_size)

   local surface_region = self:_convert_height_map_to_region3(height_map, self._add_land_to_region)
   region3:add_region(surface_region)

   -- VANILLA COMMENT: will overwrite some cubes from the surface region
   -- The fact is that whole overwriting is a source of problems so we disable it
   if not self._biome._terrain_info.custom_types then
      local underground_region = self:_convert_height_map_to_region3(underground_height_map, self._add_land_to_region)
      region3:add_region(underground_region)
   end

   local bedrock_height = (self._biome._terrain_info.custom_parameters and self._biome._terrain_info.custom_parameters.bedrock_height) and self._biome._terrain_info.custom_parameters.bedrock_height or 4
   local add_bedrock = true
   if stonehearth.game_creation.get_extra_map_options then
      local custom_map_options = stonehearth.game_creation:get_extra_map_options()
      if not (custom_map_options.modes and custom_map_options.modes.sky_lands) then
         add_bedrock = false
      end
   end
   if add_bedrock then
      local bedrock_region = self:_get_bedrock_region(height_map, bedrock_height)
      region3:add_region(bedrock_region)
   end

   region3:optimize('CustomHeightMapRenderer:render_height_map_to_region()')
end

function CustomHeightMapRenderer:_add_land_to_region(region3, rect, height)
   local terrain_type = self._biome:get_terrain_type(height)
   if self._terrain_type_uses_custom_function[terrain_type] then
      self:_add_custom_type_to_region(region3, rect, height, terrain_type)
   else
      self._add_land_functions[terrain_type](self, region3, rect, height)
   end
end

-- NEW FUNCTION!
function CustomHeightMapRenderer:_add_custom_type_to_region(region3, rect, height, terrain_type)
   local function get_custom_type_params(biome_instance, terrain_type)
      if biome_instance._terrain_info.custom_types and biome_instance._terrain_info.custom_types[terrain_type] then
         return biome_instance._terrain_info.custom_types[terrain_type].generator, biome_instance._terrain_info.custom_types[terrain_type].pre_process
      end
      return nil, nil
   end

   local generator, pre_process = get_custom_type_params(self._biome, terrain_type)
   local core_height = height
   -- add post-processing blocks
   if pre_process then
      if pre_process.method == 'top_grass' then
         if height <= pre_process.max_height then
            core_height = height - pre_process.grass_height
            region3:add_unique_cube(Cube3(
               Point3(rect.min.x, core_height, rect.min.y),
               Point3(rect.max.x, height, rect.max.y),
               self._block_types[pre_process.grass_type]
            ))
         end
      elseif pre_process.method == 'top_snow' then
         core_height = height - pre_process.snow_height
         if height >= pre_process.min_height then
            region3:add_unique_cube(Cube3(
               Point3(rect.min.x, core_height, rect.min.y),
               Point3(rect.max.x, height, rect.max.y),
               self._block_types[pre_process.snow_type]
            ))
         end
      elseif pre_process.method == 'top_soil_strata_and_grass' then
         core_height = height - pre_process.grass_height - pre_process.soil_height
         self:_add_soil_strata_to_region(region3, Cube3(
            Point3(rect.min.x, core_height, rect.min.y),
            Point3(rect.max.x, height - pre_process.grass_height, rect.max.y)
         ), pre_process.strata_height, pre_process.num_strata)

         region3:add_unique_cube(Cube3(
            Point3(rect.min.x, height - pre_process.grass_height, rect.min.y),
            Point3(rect.max.x, height, rect.max.y),
            self._block_types[pre_process.grass_type]
         ))
      end
   end

   -- add what's left using the core method
   if core_height >= 1 then
      if generator.method == 'static' then
         region3:add_unique_cube(Cube3(
               Point3(rect.min.x, 0, rect.min.y),
               Point3(rect.max.x, core_height, rect.max.y),
               self._block_types[generator.type]
            ))
      elseif generator.method == 'layer' then
         local block_max
         local block_min = 0
         local stop = false

         for i = 1,#(self._custom_layer_definitions[generator.type]) do
            if (i == #(self._custom_layer_definitions[generator.type])) or (core_height <= self._custom_layer_definitions[generator.type][i].max_height) then
               block_max = core_height
               stop = true
            else
               block_max = self._custom_layer_definitions[generator.type][i].max_height
            end
            region3:add_unique_cube(Cube3(
                  Point3(rect.min.x, block_min, rect.min.y),
                  Point3(rect.max.x, block_max, rect.max.y),
                  self._custom_layer_definitions[generator.type][i].terrain_tag
               ))
            if stop then return end
            block_min = block_max
         end
      end
   end
end

function CustomHeightMapRenderer:_add_soil_strata_to_region(region3, cube3, strata_height, num_strata)
   strata_height = strata_height or 2
   num_strata = num_strata or 2
   local strata_period = strata_height * num_strata
   local y_min = cube3.min.y
   local y_max = cube3.max.y
   local j_min = math.floor(cube3.min.y / strata_height) * strata_height
   local j_max = cube3.max.y

   for j = j_min, j_max, strata_height do
      local lower = math.max(j, y_min)
      local upper = math.min(j+strata_height, y_max)
      local block_type = j % strata_period == 0 and self._block_types.soil_light or self._block_types.soil_dark

      region3:add_unique_cube(Cube3(
            Point3(cube3.min.x, lower, cube3.min.z),
            Point3(cube3.max.x, upper, cube3.max.z),
            block_type
         ))
   end
end

return CustomHeightMapRenderer
