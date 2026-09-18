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
