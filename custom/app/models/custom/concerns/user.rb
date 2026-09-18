# Injetado em User por User.include_mod_with('Concerns::User').
module Custom::Concerns::User
  extend ActiveSupport::Concern

  included do
    has_many :funnel_board_members, class_name: 'Funnel::BoardMember', dependent: :destroy
    has_many :funnel_boards, through: :funnel_board_members, source: :board
    has_many :funnel_task_assignees, class_name: 'Funnel::TaskAssignee', dependent: :destroy
    has_many :assigned_funnel_tasks, through: :funnel_task_assignees, source: :task
  end
end
