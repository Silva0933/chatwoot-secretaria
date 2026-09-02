json.id task.id
json.title task.title
json.description task.description
json.priority task.priority
json.funnel_board_id task.funnel_board_id
json.funnel_step_id task.funnel_step_id
# rank vai como string: em decimal(30,15) o JSON.parse do navegador perderia precisao no float.
json.rank task.rank.to_s
json.start_at task.start_at
json.due_at task.due_at
json.overdue task.overdue?
json.archived_at task.archived_at
json.lock_version task.lock_version
json.custom_attributes task.custom_attributes
json.created_at task.created_at
json.updated_at task.updated_at

json.assignees task.assignees.map { |user| { id: user.id, name: user.name, avatar_url: user.avatar_url } }
json.labels task.labels.map { |label| { id: label.id, title: label.title, color: label.color } }
json.contacts task.contacts.map { |contact| { id: contact.id, name: contact.name } }
json.conversations task.task_conversations.map do |link|
  json.id link.conversation.display_id
  json.conversation_id link.conversation_id
  json.is_primary link.is_primary
  json.inbox_id link.conversation.inbox_id
end
