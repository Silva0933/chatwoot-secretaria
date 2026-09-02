class Funnel::Board < ApplicationRecord
  belongs_to :account

  has_many :members, class_name: 'Funnel::BoardMember', foreign_key: :funnel_board_id, dependent: :destroy, inverse_of: :board
  has_many :board_inboxes, class_name: 'Funnel::BoardInbox', foreign_key: :funnel_board_id, dependent: :destroy, inverse_of: :board
  has_many :inboxes, through: :board_inboxes
  has_many :steps, -> { order(:rank) }, class_name: 'Funnel::Step', foreign_key: :funnel_board_id, dependent: :destroy, inverse_of: :board
  has_many :tasks, class_name: 'Funnel::Task', foreign_key: :funnel_board_id, dependent: :destroy, inverse_of: :board

  validates :name, presence: true, length: { maximum: 255 }
  validates :currency, format: { with: /\A[A-Z]{3}\z/ }

  scope :active, -> { where(archived_at: nil) }

  after_commit :dispatch_updated, on: [:create, :update]

  # Mudanca no quadro redesenha as colunas inteiras, entao o evento carrega o quadro com as
  # etapas em vez de so o que mudou.
  def push_event_data
    {
      id: id,
      name: name,
      description: description,
      currency: currency,
      archived_at: archived_at,
      steps: steps.ordered.map do |step|
        { id: step.id, name: step.name, description: step.description, color: step.color,
          rank: step.rank.to_s, stage_type: step.stage_type, probability: step.probability }
      end
    }
  end

  def archived?
    archived_at.present?
  end

  def entry_step
    steps.stage_open.first
  end

  private

  def dispatch_updated
    Rails.configuration.dispatcher.dispatch('funnel.board.updated', Time.zone.now, board: self)
  end
end
