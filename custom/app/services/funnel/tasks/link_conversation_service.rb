# Vincula uma conversa a um card. Um card aceita N conversas; o que a regra do produto proibe
# e a mesma conversa em dois cards ATIVOS do mesmo quadro. O unique index parcial em
# funnel_task_conversations e quem garante isso sob concorrencia.
class Funnel::Tasks::LinkConversationService
  class AlreadyLinked < StandardError; end

  def initialize(task:, conversation:, primary: false, actor: nil, source: 'web')
    @task = task
    @conversation = conversation
    @primary = primary
    @actor = actor
    @source = source
  end

  def perform
    link = nil

    ActiveRecord::Base.transaction do
      demote_current_primary if @primary
      link = @task.task_conversations.create!(conversation: @conversation, is_primary: @primary)
      record_event
    end

    link
  rescue ActiveRecord::RecordNotUnique
    # Corrida perdida contra outro processo: o index barrou depois da validacao passar.
    raise AlreadyLinked, 'conversation is already linked to an active task on this board'
  end

  private

  def demote_current_primary
    @task.task_conversations.where(is_primary: true).update_all(is_primary: false, updated_at: Time.current)
  end

  def record_event
    Funnel::TaskEvent.create!(
      task: @task,
      account_id: @task.account_id,
      actor: @actor,
      event_type: 'task.conversation_linked',
      source: @source,
      data_after: { conversation_id: @conversation.id, is_primary: @primary }
    )
  end
end
