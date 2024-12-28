local FormationTaskGroup = radiant.class()

FormationTaskGroup.name = 'unit formation'
FormationTaskGroup.does = 'stonehearth:formation:unit'
FormationTaskGroup.priority = 10

FormationTaskGroup.tasks = {
   'fortuna_romanorum:hold_the_line_action',
   'fortuna_romanorum:charge_action',
   'fortuna_romanorum:shield_wall_action',
   'fortuna_romanorum:wedge_action',
}

function FormationTaskGroup:initialize()
   -- Initialize the task group
   self._task_group = radiant.entities.add_task_group(self._sv.entity, self)
end

function FormationTaskGroup:start(ctx, data)
   -- Start the task group
   for _, task_name in ipairs(FormationTaskGroup.tasks) do
      self:_create_task(task_name)
   end
end

function FormationTaskGroup:stop()
   -- Stop the task group
   if self._task_group then
      self._task_group:destroy()
      self._task_group = nil
   end
end

function FormationTaskGroup:run_task(ctx, data)
   -- Define how the task group should run
   for _, task_name in ipairs(FormationTaskGroup.tasks) do
      self:_run_task(task_name)
   end
end

function FormationTaskGroup:_create_task(task_name)
   local task = radiant.create_controller(task_name, self._sv.entity)
   table.insert(self._tasks, task)
end

function FormationTaskGroup:_run_task(task_name)
   local task = self._tasks[task_name]
   if task then
      task:start(self._sv.ctx, self._sv.data)
   end
end

return FormationTaskGroup
