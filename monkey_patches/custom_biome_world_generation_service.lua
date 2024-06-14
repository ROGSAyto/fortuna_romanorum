-- local Array2D = require 'stonehearth.services.server.world_generation.array_2D'
-- local FilterFns = require 'stonehearth.services.server.world_generation.filter.filter_fns'
-- local Biome = require 'stonehearth.services.server.world_generation.biome'
-- local BlueprintGenerator = require 'stonehearth.services.server.world_generation.blueprint_generator'
-- local MicroMapGenerator = require 'stonehearth.services.server.world_generation.micro_map_generator'
-- local Landscaper = require 'stonehearth.services.server.world_generation.landscaper'
-- local TerrainGenerator = require 'stonehearth.services.server.world_generation.terrain_generator'
-- local HeightMapRenderer = require 'stonehearth.services.server.world_generation.height_map_renderer'
-- local HabitatManager = require 'stonehearth.services.server.world_generation.habitat_manager'
-- local OverviewMap = require 'stonehearth.services.server.world_generation.overview_map'
-- local ScenarioIndex = require 'stonehearth.services.server.world_generation.scenario_index'
-- local OreScenarioSelector = require 'stonehearth.services.server.world_generation.ore_scenario_selector'
-- local SurfaceScenarioSelector = require 'stonehearth.services.server.world_generation.surface_scenario_selector'
-- local DetachedRegionSet = require 'stonehearth.services.server.world_generation.detached_region_set'
local Timer = require 'stonehearth.services.server.world_generation.timer'
-- local RandomNumberGenerator = _radiant.math.RandomNumberGenerator
-- local Point2 = _radiant.csg.Point2
-- local Rect2 = _radiant.csg.Rect2
-- local Region2 = _radiant.csg.Region2
local Point3 = _radiant.csg.Point3
-- local Cube3 = _radiant.csg.Cube3
-- local Region3 = _radiant.csg.Region3
local log = radiant.log.create_logger('world_generation')

-- local WorldGenerationService = require 'stonehearth.services.server.world_generation.world_generation_service'
local CustomWorldGenerationService = class()

local VERSIONS = {
   ZERO = 0,
   MAKE_BIOME_PUBLIC = 1,
   MAKE_BIOME_NOT_CONTROLLER = 2,
   POPULATION_FACTION_ISOLATION = 3,
   ADVENTURE_MODE_FIRST_REVAMP = 4
}

function CustomWorldGenerationService:get_version()
   return VERSIONS.ADVENTURE_MODE_FIRST_REVAMP
end

function CustomWorldGenerationService:_generate_tile_internal(i, j)
   local blueprint = self._blueprint
   local tile_size = self._biome_generation_data:get_tile_size()
   local tile_map, underground_tile_map, tile_info, tile_seed
   local micro_map, underground_micro_map
   local elevation_map, underground_elevation_map, feature_map, sky_map, habitat_map
   local offset_x, offset_y
   local metadata = {}

   tile_info = blueprint:get(i, j)
   assert(not tile_info.generated)

   log:info('Generating tile (%d,%d)', i, j)

   -- calculate the world offset of the tile
   offset_x, offset_y = self:get_tile_origin(i, j, blueprint)

   -- make each tile deterministic on its coordinates (and game seed)
   tile_seed = self:_get_tile_seed(i, j)
   self._rng:set_seed(tile_seed)

   -- get the various maps from the blueprint
   micro_map = tile_info.micro_map
   underground_micro_map = tile_info.underground_micro_map
   elevation_map = tile_info.elevation_map
   underground_elevation_map = tile_info.underground_elevation_map
   feature_map = tile_info.feature_map
   sky_map = tile_info.sky_map
   habitat_map = tile_info.habitat_map

   -- generate the high resolution heightmap for the tile
   local seconds = Timer.measure(
      function()
         tile_map = self._terrain_generator:generate_tile(i,j,micro_map)
         underground_tile_map = self._terrain_generator:generate_underground_tile(underground_micro_map)
      end
   )
   log:info('Terrain generation time: %.3fs', seconds)
   self:_yield()

   -- render heightmap to region3
   local tile_region = self:_render_heightmap_to_region(tile_map, underground_tile_map)
   self:_yield()

   if sky_map then
      metadata.sky_region = self:_place_sky(tile_region, tile_map, sky_map, offset_x, offset_y)
      metadata.sky_region:translate(Point3(offset_x, 0, offset_y))
      self:_yield()
   end

   -- place lakes and rivers before adding to terrain so we can get the ring tesselation
   -- CRITICAL: changes function argument from tile_map to elevation_map
   metadata.water_region = self:_place_water_bodies(tile_region, elevation_map, feature_map)
   metadata.water_region:translate(Point3(offset_x, 0, offset_y))
   self:_yield()

   self:_add_region_to_terrain(tile_region, offset_x, offset_y)
   self:_yield()

   -- place flora
   self:_place_flora(tile_map, feature_map, offset_x, offset_y)
   self:_yield()

   -- place scenarios
   -- INCONSISTENCY: Ore veins extend across tiles that are already generated, but are truncated across tiles
   -- that have yet to be generated.
   self:_place_scenarios(habitat_map, elevation_map, underground_elevation_map, offset_x, offset_y)
   self:_yield()

   tile_info.generated = true

   return metadata
end

return CustomWorldGenerationService
