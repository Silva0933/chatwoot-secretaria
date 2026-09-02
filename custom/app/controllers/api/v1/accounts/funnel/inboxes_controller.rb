# Caixas de entrada ligadas ao quadro. Ligar uma caixa e o que permite, mais adiante, criar card
# automaticamente para conversa que chega por ela.
class Api::V1::Accounts::Funnel::InboxesController < Api::V1::Accounts::Funnel::BaseController
  before_action :fetch_board
  before_action :check_authorization

  def update
    ids = Array(params[:inbox_ids]).map(&:to_i)
    # Caixa de outra conta nao entra: o id vem do cliente, e o quadro so pode apontar para o que
    # a propria conta enxerga.
    ids &= Current.account.inboxes.pluck(:id)

    ActiveRecord::Base.transaction do
      @board.board_inboxes.where.not(inbox_id: ids).destroy_all
      (ids - @board.board_inboxes.pluck(:inbox_id)).each { |id| @board.board_inboxes.create!(inbox_id: id) }
    end

    @board.reload
    render 'api/v1/accounts/funnel/boards/show'
  end

  private

  def fetch_board
    @board = Current.account.funnel_boards.find(params[:board_id])
  end

  def check_authorization
    authorize(@board, :manage_settings?)
  end
end
