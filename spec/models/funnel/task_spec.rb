require 'rails_helper'

RSpec.describe Funnel::Task do
  let(:account) { create(:account) }
  let(:board) { create(:funnel_board, account: account) }

  describe 'validations' do
    it 'requires a title' do
      task = build(:funnel_task, board_for_task: board, title: nil)

      expect(task).not_to be_valid
      expect(task.errors[:title]).to be_present
    end

    it 'rejects a step that belongs to another board' do
      foreign_step = create(:funnel_step, board: create(:funnel_board, account: account))
      task = build(:funnel_task, board_for_task: board, step: foreign_step)

      expect(task).not_to be_valid
      expect(task.errors[:step]).to include('must belong to the same board as the task')
    end

    it 'rejects a board from another account' do
      task = build(:funnel_task, board_for_task: board, account: create(:account))

      expect(task).not_to be_valid
      expect(task.errors[:board]).to include('must belong to the same account as the task')
    end
  end

  describe 'defaults on create' do
    it 'copies the account from the board' do
      task = described_class.create!(board: board, step: create(:funnel_step, board: board), title: 'Novo paciente')

      expect(task.account_id).to eq(account.id)
    end

    it 'appends the card to the end of its step' do
      step = create(:funnel_step, board: board)
      first = described_class.create!(board: board, step: step, title: 'Primeiro')
      second = described_class.create!(board: board, step: step, title: 'Segundo')

      expect(second.rank).to be > first.rank
    end
  end

  describe 'archiving' do
    let(:conversation) { create(:conversation, account: account) }
    let(:task) { create(:funnel_task, board_for_task: board) }

    before { Funnel::TaskConversation.create!(task: task, conversation: conversation) }

    it 'releases the conversation link so a new card can be opened' do
      task.update!(archived_at: Time.current)

      expect(task.task_conversations.first.reload.active).to be false
    end

    it 'reactivates the link when the card is restored' do
      task.update!(archived_at: Time.current)
      task.update!(archived_at: nil)

      expect(task.task_conversations.first.reload.active).to be true
    end
  end

  describe '#overdue?' do
    it 'is true for an active card past its due date' do
      task = create(:funnel_task, board_for_task: board, due_at: 1.day.ago)

      expect(task).to be_overdue
    end

    it 'is false for an archived card' do
      task = create(:funnel_task, board_for_task: board, due_at: 1.day.ago, archived_at: Time.current)

      expect(task).not_to be_overdue
    end

    it 'is false without a due date' do
      expect(create(:funnel_task, board_for_task: board)).not_to be_overdue
    end
  end
end
