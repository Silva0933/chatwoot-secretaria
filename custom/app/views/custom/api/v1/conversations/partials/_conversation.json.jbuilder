# O cliente do fazer.ai agents resolve o card de uma conversa lendo kanban_task do payload dela,
# poupando uma segunda chamada. Renderizado a partir do partial do core, do mesmo jeito que ele
# ja renderiza o do enterprise.
#
# A escolha do card mora em Funnel::Task.for_conversation, compartilhada com o endpoint
# kanban/conversation_cards: as duas precisam apontar para o mesmo card.
task = Funnel::Task.for_conversation(conversation.id)

if task.present?
  json.kanban_task do
    json.partial! 'api/v1/accounts/kanban/tasks/task', task: task
  end
else
  json.kanban_task nil
end
