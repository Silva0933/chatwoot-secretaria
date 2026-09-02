class Api::V1::Accounts::Funnel::BoardsController < Api::V1::Accounts::Funnel::BaseController
  before_action :fetch_board, except: [:index, :create]
  before_action :check_authorization

  def index
    @boards = policy_scope(Current.account.funnel_boards.active).includes(:steps, :members)
  end

  def show; end

  def create
    @board = Funnel::Boards::CreateService.new(
      account: Current.account,
      params: permitted_params,
      creator: Current.user,
      template: params[:template].presence || :clinic
    ).perform
    render :show
  end

  def update
    @board.update!(permitted_params)
    render :show
  end

  # Arquivar e o padrao: excluir um quadro levaria junto o historico de atendimento dos cards.
  def destroy
    @board.update!(archived_at: Time.current)
    head :ok
  end

  private

  def fetch_board
    @board = Current.account.funnel_boards.find(params[:id])
  end

  # O check_authorization do Api::BaseController deriva o model de controller_name, o que aqui
  # daria "Board" e nao resolveria. Passamos o model do namespace explicitamente; a policy e o
  # scope o Pundit encontra sozinho a partir dele.
  def check_authorization
    authorize(@board || Funnel::Board)
  end

  def permitted_params
    params.require(:board).permit(:name, :description)
  end
end
