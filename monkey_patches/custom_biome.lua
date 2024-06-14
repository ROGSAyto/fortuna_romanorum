local constants = require 'stonehearth.constants'
local NonUniformQuantizer = require 'stonehearth.lib.math.non_uniform_quantizer'
-- local Point2 = _radiant.csg.Point2
-- local Rect2 = _radiant.csg.Rect2
-- local Region2 = _radiant.csg.Region2
-- local math_floor = math.floor
-- local math_ceil = math.ceil

local CustomBiome = class()
--[[
CustomBiome.lua

Monkey-patching this file works if the changes in question are effective only while creating new game.
However, this is hardly ever the case. It creates a game-breaking problem: for saved games Biome.lua is always used in its vanilla form.
The reason it happens is the class is called during World Generation service initialize() function.
The first round of patching happens immediately after launching the game. It means the class gets patched before it is instantiated.
However, when a game is loaded services are initialize()'d prior to patching so the patches have no effect.
As a result, all classes instantiated during service initialization have to be overriden instead of being patched
OR the code has to be written in a way which makes it work with both versions of Biome.lua.
]]--

--[[
function CustomBiome:__init(biome_alias, config_file_path)
   self._terrain_types = { 'plains', 'foothills', 'mountains' }
   self._tile_size = constants.terrain.TILE_SIZE
   self._macro_block_size = constants.terrain.MACRO_BLOCK_SIZE
   self._feature_block_size = constants.terrain.FEATURE_BLOCK_SIZE
   self._slice_size = constants.mining.Y_CELL_SIZE

   assert(self._tile_size % self._macro_block_size == 0)
   assert(self._macro_block_size / self._feature_block_size == 2)

   self._landscape_info = nil
   self._terrain_detail_info = nil
   self._terrain_info = nil
   self._season = nil
   self._palettes = nil
   self._biome_alias = biome_alias

   local json = radiant.resources.load_json(config_file_path)
   self._landscape_info = json.landscape
   self._terrain_detail_info = json.terrain_detailer
   self._terrain_info = self:_generate_terrain_info(json)
   self._season = json.season
   self._palettes = json.palettes
   self._json_path = config_file_path

   self:_generate_quantizers()
   self:_generate_color_map()
   self:_generate_custom_name_map()
end
]]--
function CustomBiome:__init(biome_alias, config_file_path)
   self._terrain_types = {}
   self._tile_size = constants.terrain.TILE_SIZE
   self._macro_block_size = constants.terrain.MACRO_BLOCK_SIZE
   self._feature_block_size = constants.terrain.FEATURE_BLOCK_SIZE
   self._slice_size = constants.mining.Y_CELL_SIZE

   assert(self._tile_size % self._macro_block_size == 0)
   assert(self._macro_block_size / self._feature_block_size == 2)

   self._landscape_info = nil
   self._terrain_detail_info = nil
   self._terrain_info = nil
   self._season = nil
   self._palettes = nil
   self._biome_alias = biome_alias

   local json = radiant.resources.load_json(config_file_path)
   if json.terrain.custom_types then
      for key, value in pairs(json.terrain.custom_types) do
      -- IMPORTANT! The code often takes element order of this list into account so make sure it is not changed anywhere!
         self._terrain_types[value.order] = key
      end
   else
      self._terrain_types = { 'plains', 'foothills', 'mountains' }
   end
   self._landscape_info = json.landscape
   self._terrain_detail_info = json.terrain_detailer
   self._terrain_info = self:_generate_terrain_info(json)
   self._season = json.season
   self._palettes = json.palettes
   self._json_path = config_file_path

   self:_generate_quantizers()
   self:_generate_color_map()
   self:_generate_custom_name_map()
end

--[[
function CustomBiome:get_terrain_type(height)
   local terrain_info = self._terrain_info

   if height <= terrain_info.plains.height_max then
      return 'plains'
   elseif height <= terrain_info.foothills.height_max then
      return 'foothills'
   else
      return 'mountains'
   end
end
]]--
function CustomBiome:get_terrain_type(height)
   local terrain_info = self._terrain_info
   if terrain_info.custom_types then
      for i, terrain_type in ipairs(self._terrain_types) do
         if height <= terrain_info[terrain_type].height_max then
            return terrain_type
         end
      end
      return self._terrain_types[#(self._terrain_types)]
   else
      if height <= terrain_info.plains.height_max then
         return 'plains'
      elseif height <= terrain_info.foothills.height_max then
         return 'foothills'
      else
         return 'mountains'
      end
   end
end

--[[
-- takes quantized height values
function CustomBiome:get_terrain_type_and_step(height)
   local terrain_info = self._terrain_info
   local terrain_type = self:get_terrain_type(height)
   local height_base = terrain_info[terrain_type].height_base
   local step_size = terrain_info[terrain_type].step_size
   local step_number = (height - height_base) / step_size
   return terrain_type, step_number
end
]]--
-- takes quantized height values (whatever it means)
function CustomBiome:get_terrain_type_and_step(height)
   local terrain_info = self._terrain_info
   local terrain_type = self:get_terrain_type(height)
   local height_base = terrain_info[terrain_type].height_base
   local step_size = terrain_info[terrain_type].step_size
-- I have no clue why no additional checks were used here given all potenital problems later on
   local step_number = height - height_base
   step_number = ( step_number - step_number % step_size ) / step_size
   step_number = step_number < 1 and 1 or step_number
   return terrain_type, step_number
end

--[[
function CustomBiome:_generate_terrain_info(json)
   -- yikes, should really clone this first
   local terrain_info = json.terrain
   local slice_size = self._slice_size

   assert(terrain_info.foothills.step_size % slice_size == 0)
   assert(terrain_info.mountains.step_size % slice_size == 0)

   -- compute terrain elevations
   local prev_terrain_type
   for i, terrain_type in ipairs(self._terrain_types) do
      local base
      if terrain_type == 'plains' then
         base = terrain_info.height_base
      else
         base = terrain_info[prev_terrain_type].height_max
      end
      terrain_info[terrain_type].height_base = base
      terrain_info[terrain_type].height_max = base + terrain_info[terrain_type].step_size * terrain_info[terrain_type].step_count
      prev_terrain_type = terrain_type
   end

   terrain_info.plains.height_valley  = terrain_info.height_base + terrain_info.plains.valley_count * terrain_info.plains.step_size
   assert(terrain_info.plains.height_max % slice_size == 0)
   terrain_info.height_min = terrain_info.plains.height_valley
   terrain_info.height_max = terrain_info.mountains.height_max

   return terrain_info
end
]]--
function CustomBiome:_generate_terrain_info(json)
   -- yikes, should really clone this first
   local terrain_info = json.terrain
   -- We're not removing the asserts because they are going to be checked on game load anyway.
   local slice_size = self._slice_size

   if terrain_info['foothills'] then
      if not (terrain_info.foothills.step_size % slice_size == 0) then
         error('Foothills step size not a multiple of slice size in biome JSON; this may still allow to generate a custom biome but will not allow to load a game with it.')
      end
   else
      error('No foothills data in biome JSON; this may still allow to generate a custom biome but will not allow to load a game with it.')
   end
   if terrain_info['mountains'] then
      if not (terrain_info.mountains.step_size % slice_size == 0) then
         error('Mountains step size not a multiple of slice size in biome JSON; this may still allow to generate a custom biome but will not allow to load a game with it.')
      end
   else
      error('No mountains data in biome JSON; this may still allow to generate a custom biome but will not allow to load a game with it.')
   end

   -- compute terrain elevations using our new unhardcoded method
   local prev_terrain_type
   for i, terrain_type in ipairs(self._terrain_types) do
      local base
      if terrain_type == self._terrain_types[1] then
         base = terrain_info.height_base
      else
         base = terrain_info[prev_terrain_type].height_max
      end
      terrain_info[terrain_type].height_base = base
      terrain_info[terrain_type].height_max = base + terrain_info[terrain_type].step_size * terrain_info[terrain_type].step_count
      prev_terrain_type = terrain_type
   end

-- TO DO: We're opting out of this one for now like the UK from the EU, byebye dirt holes!
   if terrain_info['plains'] then
      terrain_info.plains.valley_count = terrain_info.plains.valley_count or 0
      terrain_info.plains.height_valley  = terrain_info.height_base + terrain_info.plains.valley_count * terrain_info.plains.step_size
      if not ((terrain_info.height_base + terrain_info.plains.step_size * terrain_info.plains.step_count) % slice_size == 0) then
         error('Sum of height base and plains total height not a multiple of slice size in biome JSON; this may still allow to generate a custom biome but will not allow to load a game with it.')
      end
   else
      error('No plains data in biome JSON; this may still allow to generate a custom biome but will not allow to load a game with it.')
   end
   terrain_info.height_min = terrain_info.height_base
   terrain_info.height_max = terrain_info[self._terrain_types[#self._terrain_types]].height_max

   return terrain_info
end

--[[
-- generate quantizers for height map quantization
function CustomBiome:_generate_quantizers()
   local centroids = self:_get_terrain_elevations()
   self._quantizer = NonUniformQuantizer(centroids)

   local mountains_centroids = self:_get_mountain_elevations()
   self._mountains_quantizer = NonUniformQuantizer(mountains_centroids)
end
]]--
-- generate quantizers for height map quantization
function CustomBiome:_generate_quantizers()
   local centroids = self:_get_terrain_elevations()
   self._quantizer = NonUniformQuantizer(centroids)

   local function _get_highest_terrain_elevations(biome_instance)
      local highest_info = biome_instance._terrain_info[biome_instance._terrain_types[#biome_instance._terrain_types]]
      local elevations = {}

      local min = highest_info.height_base % highest_info.step_size
      local max = highest_info.height_max
      local step_size = highest_info.step_size
      for value = min, max, step_size do
         table.insert(elevations, value)
      end

      return elevations
   end

   local mountains_centroids = _get_highest_terrain_elevations(self)
   self._mountains_quantizer = NonUniformQuantizer(mountains_centroids)
end

--[[
function CustomBiome:_generate_color_map()
   local palette = self._palettes[self._season]
   local minimap_palette = self._palettes.minimap
   local elevations = self:_get_terrain_elevations()
   local color_map = {
      water = minimap_palette and minimap_palette.water or '#1CBFFF',
      trees = minimap_palette and minimap_palette.trees or '#263C2C'
   }

   for _, elevation in ipairs(elevations) do
      local terrain_type, step = self:get_terrain_type_and_step(elevation)
      local terrain_code = self:_assemble_terrain_code(terrain_type, step)
      local color

      if terrain_type == 'plains' then
         color = step <= 1 and palette.dirt or palette.grass
      elseif terrain_type == 'foothills' then
         color = palette.grass_hills
      elseif terrain_type == 'mountains' then
         color = palette['rock_layer_' .. step]
      else
         error('unknown terrain type')
      end

      if minimap_palette and minimap_palette[terrain_code] then
         color = minimap_palette[terrain_code]
      end

      color_map[terrain_code] = color
   end

   self._color_map = color_map
end
]]--
function CustomBiome:_generate_color_map()
   local palette = self._palettes[self._season]
   local minimap_palette = self._palettes.minimap
   local elevations = self:_get_terrain_elevations()
   local color_map = {
      water = minimap_palette and minimap_palette.water or '#1CBFFF',
      trees = minimap_palette and minimap_palette.trees or '#263C2C'
   }
   if self._terrain_info.custom_types then
      for _, elevation in ipairs(elevations) do
         local terrain_type, step = self:get_terrain_type_and_step(elevation)
         local terrain_code = self:_assemble_terrain_code(terrain_type, step)
         local color

         local custom_terrain_palette = self._terrain_info.custom_types[terrain_type] and self._terrain_info.custom_types[terrain_type].palette
         if custom_terrain_palette and custom_terrain_palette.method then
            if custom_terrain_palette.method == 'static' then
               color = palette[custom_terrain_palette.type]
            elseif custom_terrain_palette.method == 'threshold' then
               color = step < custom_terrain_palette.threshold and palette[custom_terrain_palette.type_below] or palette[custom_terrain_palette.type_at_and_above]
            elseif custom_terrain_palette.method == 'layer' then
               color = palette[custom_terrain_palette.type .. '_layer_' .. step]
            end
         else
            error('unknown custom terrain type or palette assignment method')
         end

         if minimap_palette and minimap_palette[terrain_code] then
            color = minimap_palette[terrain_code]
         end

         color_map[terrain_code] = color
      end
   else
      for _, elevation in ipairs(elevations) do
         local terrain_type, step = self:get_terrain_type_and_step(elevation)
         local terrain_code = self:_assemble_terrain_code(terrain_type, step)
         local color

         if terrain_type == 'plains' then
            color = step <= 1 and palette.dirt or palette.grass
         elseif terrain_type == 'foothills' then
            color = palette.grass_hills
         elseif terrain_type == 'mountains' then
            color = palette['rock_layer_' .. step]
         else
            error('unknown terrain type')
         end

         if minimap_palette and minimap_palette[terrain_code] then
            color = minimap_palette[terrain_code]
         end

         color_map[terrain_code] = color
      end
   end
   self._color_map = color_map
end

return CustomBiome
