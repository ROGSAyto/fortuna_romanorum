local ClamTaskGroup = class()
ClamTaskGroup.name = 'clam movement'
ClamTaskGroup.does = 'stonehearth:top'
ClamTaskGroup.priority = 1

return stonehearth.ai:create_task_group(ClamTaskGroup)
:declare_task('stonehearth:goto_entity', 1)
