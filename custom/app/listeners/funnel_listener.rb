# Leva as mudancas do Kanban para os navegadores abertos.
#
# Quem recebe nao e a conta inteira: e quem pode ver aquele quadro. Um agente que nao e membro
# do quadro nao enxerga os cards dele na API, e mandar o titulo de um card pelo websocket
# contornaria a policy pela porta dos fundos.
class FunnelListener < BaseListener
  def funnel_task_created(event)
    broadcast_task(event, 'funnel.task.created')
  end

  def funnel_task_updated(event)
    broadcast_task(event, 'funnel.task.updated')
  end

  def funnel_task_moved(event)
    broadcast_task(event, 'funnel.task.moved')
  end

  # Arquivar e o nosso excluir: para o quadro aberto, o card tem de sumir.
  def funnel_task_deleted(event)
    task = event.data[:task]
    broadcast_to_board(task.board, 'funnel.task.deleted', { id: task.id, funnel_board_id: task.funnel_board_id })
  end

  # O card desenha dados da CONVERSA: o trecho e a ultima mensagem do cliente e o relogio e o
  # waiting_since dela. Nenhum dos dois toca o registro do card, entao nenhum evento de funil
  # nascia e o quadro aberto so se mexia quando alguem arrastava um card — o unico gesto que
  # dispara funnel.task.moved. Mensagem nova ficava invisivel ate alguem recarregar a pagina.
  #
  # A condicao espelha o que Funnel::ConversationPreviews seleciona (incoming, nao privada): sao
  # exatamente as mensagens que mudam o trecho, e mais nenhuma. Resposta do agente nao entra aqui
  # porque nao muda o trecho — ela zera o waiting_since, e isso chega por conversation_updated.
  def message_created(event)
    message = event.data[:message]
    return if message.blank? || message.private? || !message.incoming?

    broadcast_conversation_tasks(message.conversation_id)
  end

  # A outra metade do relogio, e tambem etiqueta, prioridade, status e responsavel: Conversation
  # lista todos em list_of_keys e so dispara com um deles.
  #
  # E o unico ponto onde o waiting_since chega ASSENTADO. Message grava o waiting_since depois de
  # despachar MESSAGE_CREATED (app/models/message.rb:500 e 506, e o comentario em
  # automation_rule_pending_execution.rb:124 diz isso com todas as letras), entao transmitir o card
  # la em cima mandaria o relogio de antes da mensagem. Aquele update dispara este evento, e e
  # aqui que o card sai com a hora certa.
  def conversation_updated(event)
    conversation = event.data[:conversation]
    return if conversation.blank?

    broadcast_conversation_tasks(conversation.id)
  end

  def funnel_board_updated(event)
    board = Funnel::Board.includes(:steps).find_by(id: event.data[:board].id)
    return if board.blank?

    broadcast_to_board(board, 'funnel.board.updated', board.push_event_data)
  end

  private

  # Carrega o card numa instancia propria em vez de usar a que veio no evento. O listener e
  # sincrono, e montar o payload percorre as associacoes: fazer isso sobre o objeto de quem
  # acabou de gravar deixa as colecoes cacheadas nele, e o chamador passa a ler uma lista vazia
  # que ele mesmo nunca pediu. Tambem garante que o payload reflete o estado ja commitado.
  def broadcast_task(event, event_name)
    task = Funnel::Task.includes(:board, :step, :assignees, :labels, :contacts,
                                 task_conversations: { conversation: { inbox: :channel } })
                       .find_by(id: event.data[:task].id)
    return if task.blank?

    broadcast_to_board(task.board, event_name, task.push_event_data)
  end

  # Um card por conversa e o caso comum, mas a mesma conversa pode estar em quadros diferentes e
  # cada quadro tem a sua propria plateia. Arquivado fica de fora: o quadro ja o removeu da tela
  # quando ele foi arquivado, e reenvia-lo o traria de volta.
  def broadcast_conversation_tasks(conversation_id)
    return if conversation_id.blank?

    task_ids = Funnel::TaskConversation.active.where(conversation_id: conversation_id).select(:funnel_task_id)
    tasks = Funnel::Task.active
                        .includes(:board, :step, :assignees, :labels, :contacts,
                                  task_conversations: { conversation: { inbox: :channel } })
                        .where(id: task_ids)

    tasks.each { |task| broadcast_to_board(task.board, 'funnel.task.updated', task.push_event_data) }
  end

  def broadcast_to_board(board, event_name, payload)
    return if board.blank?

    account = board.account
    tokens = board_tokens(account, board)
    return if tokens.blank?

    ::ActionCableBroadcastJob.perform_later(tokens, event_name, payload.merge(account_id: account.id))
  end

  # Administrador enxerga todo quadro da conta; os demais, so aqueles de que sao membros. Mesma
  # regra de Funnel::BoardPolicy::Scope.
  def board_tokens(account, board)
    admin_tokens = account.administrators.pluck(:pubsub_token)
    member_tokens = User.where(id: board.members.select(:user_id)).pluck(:pubsub_token)

    (admin_tokens + member_tokens).compact.uniq
  end
end
