class Api::V1::Accounts::Kanban::BoardStepsController < Api::V1::Accounts::Kanban::BaseController
  before_action :fetch_board
  before_action :check_authorization

  def index
    @steps = @board.steps.ordered
  end

  def create
    @board.steps.create!(permitted_params)
    @steps = @board.reload.steps.ordered
    render :index
  end

  private

  def fetch_board
    @board = fetch_board!(params[:board_id])
  end

  # Listar etapas so exige ver o quadro; criar exige poder mexer nas configuracoes dele.
  def check_authorization
    authorize(@board, action_name == 'index' ? :show? : :manage_settings?)
  end

  def permitted_params
    params.require(:step).permit(:name, :description, :color, :stage_type)
  end
end
