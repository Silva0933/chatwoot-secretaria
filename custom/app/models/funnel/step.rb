class Funnel::Step < ApplicationRecord
  belongs_to :board, class_name: 'Funnel::Board', foreign_key: :funnel_board_id, inverse_of: :steps
  has_many :tasks, class_name: 'Funnel::Task', foreign_key: :funnel_step_id, dependent: :restrict_with_error, inverse_of: :step

  # open = etapa em andamento; won/lost fecham o card. Ao contrario da referencia, nao ha
  # limite de uma etapa ganha ou perdida por quadro: clinica precisa de "Faltou" e "Perdido"
  # como desfechos distintos, e ambos sao lost.
  enum stage_type: { open: 0, won: 1, lost: 2 }, _prefix: :stage

  validates :name, presence: true, length: { maximum: 255 }
  validates :color, format: { with: /\A#(?:[0-9a-fA-F]{3}){1,2}\z/ }
  validates :rank, presence: true

  before_validation :assign_default_rank, on: :create

  scope :ordered, -> { order(:rank) }

  private

  def assign_default_rank
    return if rank.present? || board.blank?

    self.rank = Funnel::Ranking.append_after(board.steps.maximum(:rank))
  end
end
