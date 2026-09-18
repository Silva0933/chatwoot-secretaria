class Funnel::BoardInbox < ApplicationRecord
  belongs_to :board, class_name: 'Funnel::Board', foreign_key: :funnel_board_id, inverse_of: :board_inboxes
  belongs_to :inbox

  validates :inbox_id, uniqueness: { scope: :funnel_board_id }
  validate :inbox_belongs_to_board_account

  private

  def inbox_belongs_to_board_account
    return if inbox.blank? || board.blank?
    return if inbox.account_id == board.account_id

    errors.add(:inbox, 'must belong to the same account as the board')
  end
end
