local BodyModelBuffScript = class()

function BodyModelBuffScript:on_buff_added(entity, buff)
   if entity:get_component('render_info') and entity:get_component('model_variants') then
      self:add_buff(entity, buff)
   else
      self._post_create_listener = radiant.events.listen_once(entity, 'radiant:entity:post_create', self:add_buff(entity, buff))
   end
end

function BodyModelBuffScript:on_buff_removed(entity, buff)
   if entity:get_component('render_info') and entity:get_component('model_variants') then
      self:remove_buff(entity, buff)
   end
end

function BodyModelBuffScript:add_buff(entity, buff)
   local script_info = buff:get_json().script_info
   local render_info = entity:get_component('render_info')
   local model_variants = entity:get_component('model_variants')

   if render_info and model_variants then
      local current_variant = render_info:get_model_variant()
      local json_variant = current_variant == "" and 'default' or current_variant
      local default_variant = model_variants:get_variant('default')

      if script_info[json_variant] then
         for model_path, enabled in pairs(script_info[json_variant]) do
            if enabled == true then
               default_variant:add_model(model_path)
            elseif enabled == false then
               default_variant:remove_model(model_path)
            end
         end
         render_info:set_model_variant(current_variant)
      end
   else
      error('Trying to apply model variant buff but render_info or model_variants component is missing from target.')
   end

   if self._post_create_listener then
      self._post_create_listener:destroy()
      self._post_create_listener = nil
   end
end

function BodyModelBuffScript:remove_buff(entity, buff)
   local script_info = buff:get_json().script_info
   local render_info = entity:get_component('render_info')
   local model_variants = entity:get_component('model_variants')

   if render_info and model_variants then
      local current_variant = render_info:get_model_variant()
      local json_variant = current_variant == "" and 'default' or current_variant
      local default_variant = model_variants:get_variant('default')

      if script_info[json_variant] then
         for model_path, enabled in pairs(script_info[json_variant]) do
            if enabled == false then
               default_variant:add_model(model_path)
            elseif enabled == true then
               default_variant:remove_model(model_path)
            end
         end
         render_info:set_model_variant(current_variant)
      end
   else
      error('Trying to remove model variant buff but render_info or model_variants component is missing from target.')
   end

   if self._post_create_listener then
      self._post_create_listener:destroy()
      self._post_create_listener = nil
   end
end

return BodyModelBuffScript