json.payload do
  json.array! @tasks do |task|
    json.partial! 'api/v1/accounts/kanban/tasks/task', task: task
  end
end
