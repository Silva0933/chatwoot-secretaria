# O caminho inverso do quadro: olhar e mexer no card a partir da conversa.
#
# O atendente vive na conversa, nao no funil. Obriga-lo a abrir o quadro, achar o card e voltar
# e o atrito que este controller existe para remover.
#
# O id na rota e o display_id da conversa, como no resto da API do core.
class Api::V1::Accounts::Funnel::ConversationTasksController < Api::V1::Accounts::Funnel::BaseController
  before_action :fetch_conversation
  before_action :check_authorization

  # Cards ativos ligados a esta conversa. Podem ser varios: a regra proibe dois cards ativos da
  # mesma conversa no MESMO quadro, nao em quadros diferentes — a mesma conversa pode viver no
  # funil comercial e no de pos-atendimento ao mesmo tempo.
  def index
    @tasks = policy_scope(
      Funnel::Task.active
                  .where(id: Funnel::TaskConversation.active.where(conversation_id: @conversation.id).select(:funnel_task_id))
    ).includes(:assignees, :labels, :contacts, :board, :step, task_conversations: { conversation: { inbox: :channel } })

    render 'api/v1/accounts/funnel/tasks/index'
  end

  def create
    board = Current.account.funnel_boards.active.find(params[:board_id])
    authorize(Funnel::Task.new(funnel_board_id: board.id), :create?)

    @task = build_task(board)

    ActiveRecord::Base.transaction do
      @task.save!
      link_contact
      Funnel::Tasks::LinkConversationService.new(
        task: @task, conversation: @conversation, primary: true, actor: Current.user
      ).perform
    end

    @task.reload
    render 'api/v1/accounts/funnel/tasks/show'
  rescue Funnel::Tasks::LinkConversationService::AlreadyLinked => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def fetch_conversation
    @conversation = Current.account.conversations.find_by!(display_id: params[:conversation_id])
  end

  # Ver e criar card exige poder ver a conversa; o que o card permite depois e a policy dele.
  def check_authorization
    authorize(@conversation, :show?)
  end

  def build_task(board)
    task = Funnel::Task.new(permitted_params)
    task.board = board
    task.step = board.steps.find_by(id: params[:funnel_step_id]) || board.entry_step
    task.created_by = Current.user
    # Sem titulo, o nome de quem esta do outro lado diz mais do que "Nova tarefa": e por ele que
    # o atendente reconhece o card no quadro.
    task.title = task.title.presence || @conversation.contact&.name.presence || "##{@conversation.display_id}"
    task
  end

  def link_contact
    contact = @conversation.contact
    return if contact.blank?

    @task.task_contacts.create!(contact: contact)
  end

  def permitted_params
    return {} if params[:task].blank?

    params.require(:task).permit(:title, :description, :priority, :due_at)
  end
end
