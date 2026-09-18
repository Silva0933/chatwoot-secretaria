# Acrescenta o card do Kanban ao payload de evento da conversa.
#
# O cliente do fazer.ai agents le conversation.kanban_task.custom_attributes de TODO evento que
# chega pelo Agent Bot (normalize.ts) e guarda esse bag como a memoria que ele tem do card. Sem a
# chave aqui, o agente grava um atributo no card com set_custom_attribute e no turno seguinte nao
# encontra o que ele mesmo escreveu: a leitura vem do espelho, nao da API.
#
# Entra por prepend porque push_data do core e uma tabela literal, sem gancho. A ultima linha de
# app/presenters/conversations/event_data_presenter.rb ja chama prepend_mod_with, e o mesmo
# gancho ja e usado pelo enterprise; o super abaixo alcanca os dois.
#
# O contato NAO recebe isto: CONTACT_PUSH_KEYS e uma allowlist e o card nao esta nela. Nome do
# quadro, nome das etapas e valor da oportunidade sao contexto de atendente, e o proprio
# comentario daquela constante cita este campo como o que vazou quando a lista era uma denylist.
module Custom::Conversations::EventDataPresenter
  def push_data
    super.merge(kanban_task: kanban_task_event_data)
  end

  private

  # `id` aqui delega para a conversa e e a chave primaria — nao o display_id que push_data
  # publica sob a chave `id`. Funnel::TaskConversation guarda a chave primaria, e e a mesma
  # leitura que o partial da conversa faz, por Funnel::Task.for_conversation.
  #
  # O toggle da conta e consultado antes da query porque push_data roda no caminho mais quente do
  # Chatwoot: uma conta sem o modulo nao paga nem o SELECT.
  def kanban_task_event_data
    return nil unless account.funnel_kanban_enabled?

    Funnel::Task.for_conversation(id)&.kanban_event_data
  end
end
