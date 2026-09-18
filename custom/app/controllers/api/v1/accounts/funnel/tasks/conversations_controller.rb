# Vinculo entre card e conversa.
#
# O id na rota e o display_id da conversa, o numero que o agente ve no Chatwoot, seguindo o
# resto da API do core. O id interno so aparece no payload, para o frontend montar links.
class Api::V1::Accounts::Funnel::Tasks::ConversationsController < Api::V1::Accounts::Funnel::Tasks::BaseController
  def create
    Funnel::Tasks::LinkConversationService.new(
      task: @task,
      conversation: conversation,
      primary: ActiveModel::Type::Boolean.new.cast(params[:primary]).present?,
      actor: Current.user
    ).perform

    @task.reload
    render 'api/v1/accounts/funnel/tasks/show'
  rescue Funnel::Tasks::LinkConversationService::AlreadyLinked => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # Promove a conversa a principal. E a que o card mostra em primeiro lugar quando ha varias.
  def update
    ActiveRecord::Base.transaction do
      Funnel::TaskConversation.demote_primary_of(@task)
      link.update!(is_primary: true)
      record_event('task.conversation_promoted', conversation_id: link.conversation_id)
    end

    @task.reload
    render 'api/v1/accounts/funnel/tasks/show'
  end

  def destroy
    unlinked_id = link.conversation_id
    link.destroy!
    record_event('task.conversation_unlinked', conversation_id: unlinked_id)

    @task.reload
    render 'api/v1/accounts/funnel/tasks/show'
  end

  private

  def conversation
    @conversation ||= Current.account.conversations.find_by!(display_id: params[:conversation_id] || params[:id])
  end

  def link
    @link ||= @task.task_conversations.find_by!(conversation_id: conversation.id)
  end

  def record_event(event_type, data_after)
    Funnel::TaskEvent.create!(
      task: @task,
      account_id: @task.account_id,
      actor: Current.user,
      event_type: event_type,
      source: 'web',
      data_after: data_after
    )
  end
end
