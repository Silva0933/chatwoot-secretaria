# Registro de cada disparo de automacao. Somente leitura pela API: quem escreve e o Runner.
class Funnel::AutomationRun < ApplicationRecord
  belongs_to :account
  belongs_to :board, class_name: 'Funnel::Board', foreign_key: :funnel_board_id, inverse_of: false
  belongs_to :task, class_name: 'Funnel::Task', foreign_key: :funnel_task_id, optional: true, inverse_of: false
  belongs_to :conversation, optional: true

  # Sem updated_at: um registro de auditoria nao muda depois de escrito.
  before_validation :stamp_created_at, on: :create

  validates :rule, :event_name, presence: true
  validates :status, inclusion: { in: %w[ok error] }

  scope :recent, -> { order(created_at: :desc) }
  scope :failures, -> { where(status: 'error') }

  private

  def stamp_created_at
    self.created_at ||= Time.current
  end
end
