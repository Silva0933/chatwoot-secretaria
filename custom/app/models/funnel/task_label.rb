class Funnel::TaskLabel < ApplicationRecord
  belongs_to :task, class_name: 'Funnel::Task', foreign_key: :funnel_task_id, inverse_of: :task_labels
  belongs_to :label

  validates :label_id, uniqueness: { scope: :funnel_task_id }
  validate :label_belongs_to_task_account

  private

  def label_belongs_to_task_account
    return if label.blank? || task.blank?
    return if label.account_id == task.account_id

    errors.add(:label, 'must belong to the same account as the task')
  end
end
