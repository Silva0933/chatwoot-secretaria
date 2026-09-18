class Api::V1::Accounts::Kanban::BoardsController < Api::V1::Accounts::Kanban::BaseController
  before_action :fetch_board, except: [:index, :create]
  before_action :check_authorization

  def index
    @boards = policy_scope(Current.account.funnel_boards.active).includes(:steps, :members)
  end

  def show; end

  def create
    @board = Funnel::Boards::CreateService.new(
      account: Current.account, params: permitted_params, creator: Current.user,
      template: params[:template].presence || :clinic
    ).perform
    render :show
  end

  def update
    @board.update!(permitted_params)
    render :show
  end

  # O agente manda o conjunto final de caixas e de agentes, entao a operacao e um diff, nao um
  # append: a mesma semantica de update_inboxes/update_agents do contrato da Pro.
  def update_inboxes
    sync(@board.board_inboxes, :inbox_id, Array(params[:inbox_ids]).map(&:to_i))
    render :show
  end

  def update_agents
    sync(@board.members, :user_id, Array(params[:agent_ids]).map(&:to_i))
    render :show
  end

  private

  def fetch_board
    @board = fetch_board!(params[:id])
  end

  # O Pundit deriva a consulta do nome da acao, e a policy nao tem update_inboxes? nem
  # update_agents?. Ambas mexem em quem enxerga o quadro, entao pedem manage_settings?.
  MEMBERSHIP_ACTIONS = %w[update_inboxes update_agents].freeze

  def check_authorization
    return authorize(@board, :manage_settings?) if MEMBERSHIP_ACTIONS.include?(action_name)

    authorize(@board || Funnel::Board)
  end

  def sync(association, foreign_key, ids)
    current = association.pluck(foreign_key)
    association.where(foreign_key => current - ids).destroy_all
    (ids - current).each { |id| association.create!(foreign_key => id) }
    @board.reload
  end

  def permitted_params
    params.require(:board).permit(:name, :description)
  end
end
