json.id task.id
json.title task.title
json.description task.description
json.priority task.priority
json.funnel_board_id task.funnel_board_id
json.funnel_step_id task.funnel_step_id
# Nome do quadro e da etapa junto do card: no painel da conversa nao ha colunas em volta para
# dizer onde ele esta, e "Agendado" sozinho nao diz de qual funil.
json.board_name task.board.name
json.step_name task.step.name
json.step_color task.step.color
json.step_stage_type task.step.stage_type
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
# O card mostra ha quanto tempo esta parado nesta etapa, nao ha quanto tempo existe: um lead
# criado ha um mes que avancou ontem nao esta travado.
json.step_changed_at task.step_changed_at

json.assignees(task.assignees.map { |user| { id: user.id, name: user.name, avatar_url: user.avatar_url } })
json.labels(task.labels.map { |label| { id: label.id, title: label.title, color: label.color } })
json.contacts(task.contacts.map { |contact| { id: contact.id, name: contact.name } })
json.conversations task.task_conversations.map do |link|
  json.id link.conversation.display_id
  json.conversation_id link.conversation_id
  json.is_primary link.is_primary
  json.inbox_id link.conversation.inbox_id
end

# De onde o atendimento veio. O card precisa disso para desenhar o icone do canal, e quem
# resolve icone no frontend e o provider do core, que le channel_type, provider e medium — os
# tres viajam juntos por isso. Sai da conversa principal: um card com varias conversas mostra a
# origem daquela que manda.
primary_conversation = task.task_conversations.detect(&:is_primary)&.conversation
primary_inbox = primary_conversation&.inbox

if primary_inbox.present?
  json.channel do
    json.inbox_id primary_inbox.id
    json.name primary_inbox.name
    json.channel_type primary_inbox.channel_type
    json.provider primary_inbox.channel.try(:provider)
    json.medium primary_inbox.channel.try(:medium)
  end
else
  json.channel nil
end
