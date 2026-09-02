class Funnel::Board < ApplicationRecord
  belongs_to :account

  has_many :members, class_name: 'Funnel::BoardMember', foreign_key: :funnel_board_id, dependent: :destroy, inverse_of: :board
  has_many :board_inboxes, class_name: 'Funnel::BoardInbox', foreign_key: :funnel_board_id, dependent: :destroy, inverse_of: :board
  has_many :inboxes, through: :board_inboxes
  has_many :steps, -> { order(:rank) }, class_name: 'Funnel::Step', foreign_key: :funnel_board_id, dependent: :destroy, inverse_of: :board
  has_many :tasks, class_name: 'Funnel::Task', foreign_key: :funnel_board_id, dependent: :destroy, inverse_of: :board

  validates :name, presence: true, length: { maximum: 255 }

  scope :active, -> { where(archived_at: nil) }

  def archived?
    archived_at.present?
  end

  def entry_step
    steps.stage_open.first
  end
end
