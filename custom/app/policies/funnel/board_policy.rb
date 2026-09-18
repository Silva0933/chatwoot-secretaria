# Permissao do modulo Funnel. Nao usa CustomRole de proposito: aquele modelo vive em enterprise/
# e sai da arvore na imagem de revenda. O papel vem de funnel_board_members, com o administrador
# da conta sempre com acesso total.
class Funnel::BoardPolicy < ApplicationPolicy
  def index?
    account_user.administrator? || account_user.agent?
  end

  def show?
    administrator? || membership.present?
  end

  def create?
    administrator?
  end

  def update?
    administrator? || membership&.role_manager?
  end

  def destroy?
    administrator?
  end

  # Etapas, membros e caixas do quadro.
  def manage_settings?
    update?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.where(account_id: account.id) if account_user.administrator?

      scope.where(account_id: account.id)
           .where(id: Funnel::BoardMember.where(user_id: user.id).select(:funnel_board_id))
    end
  end

  private

  def administrator?
    account_user.administrator?
  end

  def membership
    return @membership if defined?(@membership)

    @membership = Funnel::BoardMember.find_by(funnel_board_id: record.id, user_id: user.id)
  end
end
