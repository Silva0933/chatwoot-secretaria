# Guarda unica do modulo: o toggle da conta e checado aqui e nao repetido nos filhos.
class Api::V1::Accounts::Funnel::BaseController < Api::V1::Accounts::BaseController
  before_action :ensure_feature_enabled

  helper_method :funnel_conversation_preview

  private

  def ensure_feature_enabled
    return if Current.account.funnel_kanban_enabled?

    render json: { error: 'Funnel Kanban is not enabled for this account' }, status: :forbidden
  end

  # O trecho da ultima mensagem do cliente, para o partial do card.
  #
  # Mora no controller, e nao no partial, porque a consulta precisa ver o quadro inteiro de uma
  # vez: chamada de dentro do laco, seria uma consulta por card. O hash e montado na primeira
  # chamada com os ids de todos os cards que estao sendo renderizados e serve as demais.
  def funnel_conversation_preview(conversation)
    return if conversation.blank?

    conversation_previews[conversation.id]
  end

  def conversation_previews
    @conversation_previews ||= Funnel::ConversationPreviews.new(primary_conversation_ids).perform
  end

  # So as conversas principais: e a delas que o card tira trecho, canal e relogio de espera.
  def primary_conversation_ids
    rendered_tasks.filter_map { |task| task.task_conversations.detect(&:is_primary)&.conversation_id }
  end

  # `@tasks` nas listagens, `@task` em show/create/update/move — os dois caminhos que renderizam
  # o partial do card.
  def rendered_tasks
    @tasks || Array(@task)
  end
end
