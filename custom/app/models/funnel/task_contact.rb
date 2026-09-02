class Funnel::TaskContact < ApplicationRecord
  belongs_to :task, class_name: 'Funnel::Task', foreign_key: :funnel_task_id, inverse_of: :task_contacts
  belongs_to :contact

  validates :contact_id, uniqueness: { scope: :funnel_task_id }
  validate :contact_belongs_to_task_account

  private

  def contact_belongs_to_task_account
    return if contact.blank? || task.blank?
    return if contact.account_id == task.account_id

    errors.add(:contact, 'must belong to the same account as the task')
  end
end
