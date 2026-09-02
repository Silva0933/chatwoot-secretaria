class Funnel::TaskPolicy < ApplicationPolicy
  def index?
    account_user.administrator? || account_user.agent?
  end

  def show?
    return true if administrator?
    return false if membership.blank?
    return true if membership.visibility_all_tasks?

    visible_to_member?
  end

  def create?
    administrator? || membership&.role_manager? || membership&.role_member?
  end

  def update?
    return true if administrator?
    return false unless membership&.role_manager? || membership&.role_member?

    membership.visibility_all_tasks? || visible_to_member?
  end

  def move?
    update?
  end

  def destroy?
    administrator? || membership&.role_manager?
  end

  # Restringe o que o agente enxerga sem depender do frontend esconder nada.
  class Scope < ApplicationPolicy::Scope
    def resolve
      base = scope.where(account_id: account.id)
      return base if account_user.administrator?

      memberships = Funnel::BoardMember.where(user_id: user.id)
      open_board_ids = memberships.visibility_all_tasks.pluck(:funnel_board_id)
      restricted_board_ids = memberships.visibility_own_tasks.pluck(:funnel_board_id)

      # Um unico left_joins com OR em SQL: encadear .or sobre relations com joins diferentes
      # levanta "Relation passed to #or must be structurally compatible".
      base.left_joins(:task_assignees)
          .where(
            'funnel_tasks.funnel_board_id IN (:open) OR (funnel_tasks.funnel_board_id IN (:restricted) ' \
            'AND (funnel_tasks.created_by_id = :uid OR funnel_task_assignees.user_id = :uid))',
            open: open_board_ids, restricted: restricted_board_ids, uid: user.id
          ).distinct
    end
  end

  private

  def administrator?
    account_user.administrator?
  end

  def membership
    return @membership if defined?(@membership)

    @membership = Funnel::BoardMember.find_by(funnel_board_id: record.funnel_board_id, user_id: user.id)
  end

  def visible_to_member?
    record.created_by_id == user.id || record.task_assignees.exists?(user_id: user.id)
  end
end
