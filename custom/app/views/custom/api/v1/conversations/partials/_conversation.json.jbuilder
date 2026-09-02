# O cliente do fazer.ai agents resolve o card de uma conversa lendo kanban_task do payload dela,
# poupando uma segunda chamada. Renderizado a partir do partial do core, do mesmo jeito que ele
# ja renderiza o do enterprise.
#
# Quando ha cards em quadros diferentes, vai o mais recente: o contrato da Pro carrega um card
# so, e o ultimo vinculo e o que descreve o atendimento em curso.
link = Funnel::TaskConversation.active
                               .where(conversation_id: conversation.id)
                               .order(created_at: :desc)
                               .first

if link&.task.present? && link.task.archived_at.nil?
  json.kanban_task do
    json.partial! 'api/v1/accounts/kanban/tasks/task', task: link.task
  end
else
  json.kanban_task nil
end
