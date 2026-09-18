# Quem participa do quadro e com que papel. O adaptador /kanban ja mexia nisso, mas so no
# formato da Pro (ids soltos); a tela precisa tambem do papel e do escopo de visibilidade, que
# sao o que de fato controla o acesso.
class Api::V1::Accounts::Funnel::MembersController < Api::V1::Accounts::Funnel::BaseController
  before_action :fetch_board
  before_action :check_authorization

  # Troca o conjunto inteiro, como os demais multiselects do modulo. Cada item traz user_id,
  # role e visibility_scope; o diff preserva a linha de quem ficou, para nao perder o papel de
  # alguem por efeito colateral de mexer noutro membro.
  def update
    incoming = normalized_members

    ActiveRecord::Base.transaction do
      @board.members.where.not(user_id: incoming.map { |member| member[:user_id] }).destroy_all
      incoming.each { |attributes| upsert_member(attributes) }
    end

    @board.reload
    render 'api/v1/accounts/funnel/boards/show'
  end

  private

  def normalized_members
    Array(params[:members]).map do |member|
      permitted = member.respond_to?(:permit) ? member.permit(:user_id, :role, :visibility_scope) : member
      permitted.to_h.symbolize_keys.merge(user_id: permitted[:user_id].to_i)
    end
  end

  # find_or_initialize preserva a linha de quem ja estava: recriar perderia o papel de alguem
  # por efeito colateral de mexer noutro membro.
  def upsert_member(attributes)
    member = @board.members.find_or_initialize_by(user_id: attributes[:user_id])
    member.role = attributes[:role].presence || member.role || 'member'
    member.visibility_scope = attributes[:visibility_scope].presence || member.visibility_scope || 'all_tasks'
    member.save!
  end

  def fetch_board
    @board = Current.account.funnel_boards.find(params[:board_id])
  end

  def check_authorization
    authorize(@board, :manage_settings?)
  end
end
