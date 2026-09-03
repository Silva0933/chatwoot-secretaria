# Liga os eventos de dominio ao motor de automacoes.
#
# Separado do FunnelListener de proposito: aquele so empurra pixel para o navegador e nao pode
# falhar de forma interessante; este muda dados. Misturar os dois faria um erro de automacao
# derrubar a atualizacao em tempo real, e vice-versa.
#
# Assincrono, ao contrario do FunnelListener: criar card, mover etapa e resolver conversa sao
# escritas, e nao devem pendurar a requisicao de quem mandou a mensagem.
class FunnelAutomationListener < BaseListener
  def conversation_created(event)
    conversation = extract_conversation(event)
    return if conversation.blank?

    boards_for(conversation).each do |board|
      runner(board, event, conversation).call('create_task_on_conversation')
      runner(board, event, conversation).call('auto_assign_task')
    end
  end

  def conversation_resolved(event)
    conversation = extract_conversation(event)
    return if conversation.blank?

    boards_for(conversation).each do |board|
      runner(board, event, conversation).call('win_task_on_conversation_resolved')
    end
  end

  def assignee_changed(event)
    conversation = extract_conversation(event)
    return if conversation.blank?

    boards_for(conversation).each do |board|
      runner(board, event, conversation).call('sync_assignees')
    end
  end

  def conversation_updated(event)
    conversation = extract_conversation(event)
    return if conversation.blank?

    boards_for(conversation).each do |board|
      runner(board, event, conversation).call('sync_labels_and_priority')
    end
  end

  # Do lado do funil: o card mudou de etapa, o que pode fechar a conversa e empurrar o
  # responsavel e a prioridade de volta.
  def funnel_task_moved(event)
    task = event.data[:task]
    return if task.blank?

    board = task.board
    runner(board, event, primary_conversation(task), task).call('resolve_conversation_on_final_step')
    runner(board, event, primary_conversation(task), task).call('sync_assignees')
    runner(board, event, primary_conversation(task), task).call('sync_labels_and_priority')
  end

  private

  def extract_conversation(event)
    event.data[:conversation]
  end

  # So os quadros ligados a caixa daquela conversa. Um quadro sem caixa vinculada nao recebe
  # nada automaticamente: ligar a caixa e o gesto que diz "este funil atende este canal".
  def boards_for(conversation)
    Funnel::Board.active
                 .where(account_id: conversation.account_id)
                 .where(id: Funnel::BoardInbox.where(inbox_id: conversation.inbox_id).select(:funnel_board_id))
                 .includes(:steps)
  end

  def primary_conversation(task)
    task.task_conversations.detect(&:is_primary)&.conversation
  end

  def runner(board, event, conversation, task = nil)
    Funnel::Automations::Runner.new(
      board: board, event_name: event.name, conversation: conversation, task: task
    )
  end
end
