# Base dos recursos aninhados em um card (responsaveis, etiquetas, contatos, conversas,
# eventos). Todos precisam do mesmo quadro, do mesmo card e da mesma autorizacao.
class Api::V1::Accounts::Funnel::Tasks::BaseController < Api::V1::Accounts::Funnel::BaseController
  before_action :fetch_board
  before_action :fetch_task
  before_action :check_authorization

  private

  def fetch_board
    @board = Current.account.funnel_boards.find(params[:board_id])
  end

  def fetch_task
    @task = Funnel::Task.where(funnel_board_id: @board.id).find(params[:task_id])
  end

  # Mexer nas associacoes de um card e edita-lo, entao a permissao e a mesma do update: quem
  # pode arrastar o card pode dizer quem e o responsavel. O Pundit deriva a policy do
  # controller_name, que aqui daria "Assignees", entao passamos o registro explicitamente.
  def check_authorization
    authorize(@task, :update?)
  end
end
