# frozen_string_literal: true

FactoryBot.define do
  factory :funnel_board, class: 'Funnel::Board' do
    account
    sequence(:name) { |n| "Funil #{n}" }
  end

  factory :funnel_step, class: 'Funnel::Step' do
    board factory: :funnel_board
    sequence(:name) { |n| "Etapa #{n}" }
    stage_type { :open }
  end

  factory :funnel_board_member, class: 'Funnel::BoardMember' do
    board factory: :funnel_board
    user
    role { :member }
    visibility_scope { :all_tasks }
  end

  factory :funnel_task, class: 'Funnel::Task' do
    transient do
      board_for_task { association(:funnel_board) }
    end

    board { board_for_task }
    step { association(:funnel_step, board: board_for_task) }
    account { board_for_task.account }
    sequence(:title) { |n| "Card #{n}" }
  end
end
