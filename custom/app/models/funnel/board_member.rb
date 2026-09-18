class Funnel::BoardMember < ApplicationRecord
  belongs_to :board, class_name: 'Funnel::Board', foreign_key: :funnel_board_id, inverse_of: :members
  belongs_to :user

  # manager administra o quadro (etapas, membros, caixas); member opera cards; viewer so le.
  # Administrador da conta ignora tudo isso e tem acesso total, ver Funnel::BoardPolicy.
  enum role: { member: 0, manager: 1, viewer: 2 }, _prefix: :role
  # own_tasks limita o agente aos cards que criou ou nos quais e responsavel.
  enum visibility_scope: { all_tasks: 0, own_tasks: 1 }, _prefix: :visibility

  validates :user_id, uniqueness: { scope: :funnel_board_id }
end
