require 'rails_helper'

RSpec.describe Funnel::TaskConversation do
  let(:account) { create(:account) }
  let(:board) { create(:funnel_board, account: account) }
  let(:other_board) { create(:funnel_board, account: account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:task) { create(:funnel_task, board_for_task: board) }

  describe 'the one active task per board rule' do
    it 'links a conversation to a task' do
      link = described_class.create!(task: task, conversation: conversation)

      expect(link.active).to be true
      expect(link.funnel_board_id).to eq(board.id)
    end

    it 'accepts many conversations on the same task' do
      described_class.create!(task: task, conversation: conversation)
      described_class.create!(task: task, conversation: create(:conversation, account: account))

      expect(task.reload.conversations.count).to eq(2)
    end

    it 'rejects a second active task for the same conversation on the same board' do
      described_class.create!(task: task, conversation: conversation)

      duplicate = described_class.new(task: create(:funnel_task, board_for_task: board), conversation: conversation)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:conversation]).to include('is already linked to an active task on this board')
    end

    it 'allows the same conversation on a task of a different board' do
      described_class.create!(task: task, conversation: conversation)

      link = described_class.new(task: create(:funnel_task, board_for_task: other_board), conversation: conversation)

      expect(link).to be_valid
    end

    # Paciente que volta meses depois precisa de um card novo na mesma jornada.
    it 'allows a new task once the previous one is archived' do
      described_class.create!(task: task, conversation: conversation)
      task.update!(archived_at: Time.current)

      link = described_class.new(task: create(:funnel_task, board_for_task: board), conversation: conversation)

      expect(link).to be_valid
    end

    it 'enforces the rule in the database even when validations are bypassed' do
      described_class.create!(task: task, conversation: conversation)

      duplicate = described_class.new(task: create(:funnel_task, board_for_task: board), conversation: conversation)

      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe 'tenant isolation' do
    it 'rejects a conversation from another account' do
      link = described_class.new(task: task, conversation: create(:conversation, account: create(:account)))

      expect(link).not_to be_valid
      expect(link.errors[:conversation]).to include('must belong to the same account as the task')
    end
  end

  describe 'single primary conversation' do
    it 'refuses two primary links on the same task at the database level' do
      described_class.create!(task: task, conversation: conversation, is_primary: true)

      duplicate = described_class.new(task: task, conversation: create(:conversation, account: account), is_primary: true)

      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
