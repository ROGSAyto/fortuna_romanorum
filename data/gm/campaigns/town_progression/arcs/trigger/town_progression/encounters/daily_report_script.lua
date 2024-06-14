local Point2 = _radiant.csg.Point2
local Point3 = _radiant.csg.Point3
local Cube3 = _radiant.csg.Cube3
local game_master_lib = require 'stonehearth.lib.game_master.game_master_lib'
local log = radiant.log.create_logger('immigration_scenario')

--[[
   FortunaRomanorumImmigration Synopsis

   Once a day, we run this scenario. It pops up a dialog showing your settlemet's core stats. 
   If your settlement meets certain conditions, cool people might want to join up. 

   The people who join are now always workers. 
]]

local SUSPENDED_BUFF = 'stonehearth:buffs:hidden:suspended'

local FortunaRomanorumImmigration = class()

function FortunaRomanorumImmigration:initialize()
   self._sv.player_id = nil
   self._sv.script_info = nil
   self._sv.citizens = {}
   self._sv.injected_ai = {}
   self._sv.chosen_citizen = nil
   self._sv.ctx = nil
   self._sv.timer = nil
   self._sv.immigration_bulletin = nil
   self._sv.searcher = nil
end

function FortunaRomanorumImmigration:restore()
   --self:_load_trade_data()

   --If we made an expire timer then we're waiting for the player to acknowledge the traveller
   --Start a timer that will expire at that time
   if self._sv.timer then
      self._sv.timer:bind(function()
            self:_timer_callback()
         end)
   end
end


function FortunaRomanorumImmigration:start(ctx, script_info)
   self._sv.player_id = ctx.player_id
   self._sv.script_info = script_info
   self._sv.ctx = ctx

   --Show a bulletin with food/net worth stats
   local message, success = self:_compose_town_report()
   local data = {
      title = self._sv.script_info.title,
      next_requirements_label = self._sv.script_info.next_requirements_label,
      message = message,
      factions = {}
   }

   if success then
      data.conclusion = self._sv.script_info.conclusion_positive
      data.accepted_callback = "_on_accepted"
      data.declined_callback = "_on_declined"
      for faction, entry in pairs(self._sv.script_info.factions) do
         self._sv.citizens[faction] = self:_create_unregistered_citizen(nil, nil, entry.citizen_info)
         data.factions[faction] = {
            ordinal = entry.ordinal,
            display_name = entry.display_name,
            citizen = self._sv.citizens[faction]
         }
      end
   else
      data.conclusion = self._sv.script_info.conclusion_negative
      data.ok_callback = "_on_declined"
   end

   self._sv.immigration_bulletin = stonehearth.bulletin_board:post_bulletin(self._sv.player_id)
      :set_ui_view('StonehearthSLImmigrationReportDialog')
      :set_callback_instance(self)
      :set_sticky(true)
      :set_data(data)

   --Make sure it times out if we don't get to it
   local wait_duration = self._sv.script_info.expiration_timeout
   self:_create_timer(wait_duration)
end

function FortunaRomanorumImmigration:_compose_town_report()
   local town_name = stonehearth.town:get_town(self._sv.player_id):get_town_name()
   local num_citizens = stonehearth.population:get_population_size(self._sv.player_id)
   local summation = self:_eval_requirement(num_citizens)

   local message = {
      date = stonehearth.calendar:get_date_data(), 
      town_name = town_name,
      town_size = num_citizens,
      food_data = summation.food_data, 
      net_worth_data = summation.net_worth_data
   }
   local success = summation.success

   return message, success
end

function FortunaRomanorumImmigration:_eval_requirement(num_citizens)
   --TODO: the score data should come from all food, not just food in stockpiles
   local score_data = stonehearth.score:get_scores_for_player(self._sv.player_id):get_score_data()
   if log:is_enabled(radiant.log.DETAIL) then
      log:detail('caculating immigration data %s', radiant.util.table_tostring(score_data))
   end

   --Get data for food
   local available_food = 0
   if score_data.total_scores:contains('edibles') then
      available_food = score_data.total_scores:get('edibles')
   end
   local food_success, food_data = self:_find_requirements_by_type_and_pop(available_food, 'food', num_citizens, 2)
   food_data.success = food_success
   log:detail('Food result: %s', radiant.util.table_tostring(food_data))

   --Get data for net worth
   local net_worth = 0
   if score_data.total_scores:contains('net_worth') then
      net_worth = score_data.total_scores:get('net_worth')
   end
   local _, net_worth_data = self:_find_requirements_by_type_and_pop(net_worth, 'net_worth', num_citizens, 3)
   -- Some town bonuses give extra net worth.
   local bonus_net_worth = 0
   local town = stonehearth.town:get_town(self._sv.player_id)
   if town then
      for _, bonus in pairs(town:get_active_town_bonuses()) do
         if bonus.get_net_worth_bonus then
            bonus_net_worth = bonus_net_worth + bonus:get_net_worth_bonus() 
         end
      end
   end
   net_worth_data.base_value = math.floor(net_worth_data.available)
   net_worth_data.bonus = math.floor(bonus_net_worth)
   net_worth_data.available = net_worth_data.base_value + net_worth_data.bonus
   net_worth_data.success = net_worth_data.available >= net_worth_data.target
   log:detail('Net Worth result: %s', radiant.util.table_tostring(net_worth_data))

   --[[-- TESTING BLOCK
   food_data.success = true
   net_worth_data.success = true
   --]]--

   local summation = {
      food_data = food_data,
      net_worth_data = net_worth_data,
      success = food_data.success and  net_worth_data.success
   }

   if (not summation.success) then
      log:debug("FortunaRomanorumImmigration unsuccessful.")
   end

   return summation
end

function FortunaRomanorumImmigration:_simplify_to_significant_figures(num, figures)
   local x = figures - math.ceil(math.log10(math.abs(num)))
   return math.floor(num*(10^x)+0.5)/(10^x)
end

function FortunaRomanorumImmigration:_find_requirements_by_type_and_pop(available, type, num_citizens, significant_figures)
   local equation = stonehearth.constants.immigration_requirements[type]
   equation = string.gsub(equation, 'num_citizens', num_citizens)
   local target = self:_evaluate_equation(equation)
   target = self:_simplify_to_significant_figures(target, significant_figures)

   local label = self._sv.script_info[type .. '_label']

   local data = {
      label = label,
      available = available, 
      target = target
   }
   local success = available >= target
   return success, data
end

function FortunaRomanorumImmigration:_evaluate_equation(equation)
   local fn = loadstring('return ' .. equation)
   return fn()
end

function FortunaRomanorumImmigration:_get_fallback_spawn_location()
   local town_center = stonehearth.town:get_town(self._sv.player_id):get_landing_location()
   -- search from max_y to avoid tunnels
   local max_y = radiant.terrain.get_terrain_component():get_bounds().max.y
   local proposed_location = radiant.terrain.get_point_on_terrain(Point3(town_center.x, max_y, town_center.z))
   local spawn_location, found = radiant.terrain.find_placement_point(proposed_location, 20, 30)
   if not found then
      spawn_location = radiant.terrain.find_placement_point(town_center, 1, 7)
   end
   return spawn_location
end

function FortunaRomanorumImmigration:_find_location_callback(op, location)
   if op == 'check_location' then
      return self:_check_location(location)
   elseif op == 'set_location' then
      self:_place_citizen(location)
   elseif op == 'abort' then
      self:_place_citizen(self._fallback_location)
   else
      radiant.error('unknown op "%s" in choose_location_outside_town callback', op)
   end
end

function FortunaRomanorumImmigration:_check_location(location)
   local r = stonehearth.terrain:get_sight_radius()
   local sight_radius = Point3(r, r, r)
   local cube = Cube3(location):inflated(sight_radius)
   local entities = radiant.terrain.get_entities_in_cube(cube)

   -- check for anything nearby that might attack the new citizen
   for _, entity in pairs(entities) do
      if entity:get_component('stonehearth:ai') then
         local player_id = radiant.entities.get_player_id(entity)
         if stonehearth.player:are_player_ids_hostile(player_id, self._sv.player_id) then
            return false
         end
      end
   end

   -- Check that it's reachable from the center of town.
   if not _radiant.sim.topology.are_strictly_connected(location, self._fallback_location, 0) then
      return false
   end
   
   return true
end

function FortunaRomanorumImmigration:_find_spawn_location()
   self._fallback_location = self:_get_fallback_spawn_location()
   self._sv.searcher = radiant.create_controller('stonehearth:game_master:util:choose_location_outside_town',
                                              64, 128,
                                              radiant.bind(self, '_find_location_callback'),
                                              nil,
                                              self._sv.player_id)
end

function FortunaRomanorumImmigration:_create_unregistered_citizen(role, gender, options)
   local pop = stonehearth.population:get_population(self._sv.player_id)
   options = options or {}
   gender = gender or pop:_pick_random_gender()
   role = role or 'default'
   local role_data, job_alias, level

   if options.population then
      local foreign_pop_json = radiant.resources.load_json(options.population)
      role_data = foreign_pop_json.roles[role]
   else
      role_data = pop:get_role_data(role)
   end
   if options.job then
      job_alias = options.job
      if options.level then
         level = options.level
      end
   else
      job_alias = stonehearth.player:get_default_base_job(self._sv.player_id)
   end

   local citizen = pop:_generate_citizen_from_role(role, role_data, gender)
   pop:_set_citizen_initial_state(citizen, gender, role_data, options)

   local job_component = citizen:add_component('stonehearth:job')
   job_component:promote_to(job_alias, { skip_visual_effects = true })
   -- ACE-only function, hence the check
   if options.population and type(job_component.set_population_override) == 'function' then
      job_component:set_population_override(options.population)
   end

   if options.level then
      for i=2, options.level do
         job_component:level_up(true) --true = skip vfx
      end
   end
   if options.equipment then
      for _, item_uri in ipairs(options.equipment) do
         local item = radiant.entities.create_entity(item_uri)
         radiant.entities.equip_item(citizen, item)
      end
   end
   if options.allowed_jobs then
      local allowed_jobs_set = {}
      for _, allowed_job in ipairs(options.allowed_jobs) do
         allowed_jobs_set[allowed_job] = true
      end
      job_component:set_allowed_jobs(allowed_jobs_set)
   end

   self._sv.injected_ai[citizen] = stonehearth.ai:inject_ai(citizen, { actions = { 'stonehearth:actions:be_away_from_town' } })
   if not radiant.entities.has_buff(citizen, SUSPENDED_BUFF) then
      radiant.entities.add_buff(citizen, SUSPENDED_BUFF)
   end

   return citizen
end

function FortunaRomanorumImmigration:_register_citizen(citizen, options)
   local pop = stonehearth.population:get_population(self._sv.player_id)
   options = options or {}
   pop._sv.citizens:add(citizen:get_id(), citizen)
   if not options.embarking then
      pop:on_citizen_count_changed()
   end
   pop:_monitor_citizen(citizen)

   --Add thoughts for new citizens.  Non-player citizens will still get this call, but if they don't have a happiness component it will be discarded.
   --Note that this may need to be revisited if we ever create alternative means for adding citizens to the town. -rhough
   radiant.entities.add_thought(citizen, 'stonehearth:thoughts:town:founding:pioneering_spirit')
   pop.__saved_variables:mark_changed()

   return citizen
end

function FortunaRomanorumImmigration:_place_citizen(location)
   if not self._sv.chosen_citizen then
      radiant.error('Expected citizen entity to place, got nil.')
   end
   radiant.terrain.place_entity(self._sv.chosen_citizen, location)
   self:_register_citizen(self._sv.chosen_citizen)

   radiant.entities.remove_buff(self._sv.chosen_citizen, SUSPENDED_BUFF)

   if self._sv.injected_ai[self._sv.chosen_citizen] then
      self._sv.injected_ai[self._sv.chosen_citizen]:destroy()
      self._sv.injected_ai[self._sv.chosen_citizen] = nil
   end

   local town = stonehearth.town:get_town(self._sv.player_id)
   --Give the entity the task to run to the banner
   self._approach_task = self._sv.chosen_citizen:get_component('stonehearth:ai')
                              :get_task_group('stonehearth:task_groups:solo:unit_control')
                                 :create_task('stonehearth:goto_town_center', {town = town})
                                 :once()
                                 :start()

   self:_inform_player(self._sv.chosen_citizen)
   self:_destroy_node()
   --TODO: attach particle effect
end

function FortunaRomanorumImmigration:_inform_player(citizen)
   --Send another bulletin with to inform player someone has joined their town
   local title = self._sv.script_info.success_title
   local pop = stonehearth.population:get_population(self._sv.player_id)
   pop:show_notification_for_citizen(citizen, title)
end

--- Only actually spawn the object after the user clicks OK
function FortunaRomanorumImmigration:_on_accepted(session, request, faction_id)
   for faction, citizen in pairs(self._sv.citizens) do
      if faction == faction_id then
         self._sv.chosen_citizen = citizen
      else
         --[[-- Probably unnecessary
         if self._sv.injected_ai[citizen] then
            self._sv.injected_ai[citizen]:destroy()
            self._sv.injected_ai[citizen] = nil
         end
         --]]--
         radiant.entities.destroy_entity(citizen)
      end
   end
   request:resolve({})

   self:_find_spawn_location()
end

function FortunaRomanorumImmigration:_on_declined()
   for faction, citizen in pairs(self._sv.citizens) do
      radiant.entities.destroy_entity(citizen)
   end
   if self._sv.timer then
      self._sv.timer:destroy()
   end
   self:_destroy_node()
end

function FortunaRomanorumImmigration:_create_timer(duration)
   self._sv.timer = stonehearth.calendar:set_persistent_timer("FortunaRomanorumImmigration remove bulletin", duration, function() 
      self:_timer_callback()
   end)
end

function FortunaRomanorumImmigration:_timer_callback()
   if self._sv.immigration_bulletin then
      local bulletin_id = self._sv.immigration_bulletin:get_id()
      stonehearth.bulletin_board:remove_bulletin(bulletin_id)
      self:_destroy_node()
   end
end

function FortunaRomanorumImmigration:_destroy_node()
   self:destroy()
   -- Remove ourselves from the lib because we don't need the data
   game_master_lib.destroy_node(self._sv.ctx.encounter, self._sv.ctx.parent_node)
end

function FortunaRomanorumImmigration:destroy()
   if self._sv.timer then
      self._sv.timer:destroy()
      self._sv.timer = nil
   end

   if self._sv.searcher then
      self._sv.searcher:destroy()
      self._sv.searcher = nil
   end
end


return FortunaRomanorumImmigration