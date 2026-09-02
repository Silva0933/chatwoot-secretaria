class Funnel::TaskConversation < ApplicationRecord
  belongs_to :task, class_name: 'Funnel::Task', foreign_key: :funnel_task_id, inverse_of: :task_conversations
  belongs_to :conversation

  # funnel_board_id e active espelham o card. Ver a migration e Funnel::Task#sync_conversation_link_columns.
  before_validation :copy_columns_from_task

  validates :conversation_id, uniqueness: { scope: :funnel_task_id }
  validate :conversation_belongs_to_task_account
  validate :single_active_task_per_board, on: :create

  scope :active, -> { where(active: true) }

  private

  def copy_columns_from_task
    return if task.blank?

    self.funnel_board_id = task.funnel_board_id
    self.active = task.archived_at.nil?
  end

  def conversation_belongs_to_task_account
    return if conversation.blank? || task.blank?
    return if conversation.account_id == task.account_id

    errors.add(:conversation, 'must belong to the same account as the task')
  end

  # O unique index parcial e a garantia real contra corrida; esta validacao existe para o erro
  # chegar ao usuario como mensagem e nao como RecordNotUnique.
  def single_active_task_per_board
    return unless active?
    return if funnel_board_id.blank? || conversation_id.blank?

    existing = self.class.active.where(funnel_board_id: funnel_board_id, conversation_id: conversation_id)
    return if existing.empty?

    errors.add(:conversation, 'is already linked to an active task on this board')
  end
end
