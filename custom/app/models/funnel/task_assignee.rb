class Funnel::TaskAssignee < ApplicationRecord
  belongs_to :task, class_name: 'Funnel::Task', foreign_key: :funnel_task_id, inverse_of: :task_assignees
  belongs_to :user

  validates :user_id, uniqueness: { scope: :funnel_task_id }
  validate :user_belongs_to_task_account

  private

  def user_belongs_to_task_account
    return if user.blank? || task.blank?
    return if AccountUser.exists?(account_id: task.account_id, user_id: user_id)

    errors.add(:user, 'must be a member of the task account')
  end
end
