json.payload do
  json.array! @tasks do |task|
    json.partial! 'api/v1/accounts/funnel/tasks/task', task: task
  end
end
