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

  # O payload de evento da conversa carrega o card (Custom::Conversations::EventDataPresenter), e
  # quem le esse payload so o recebe quando a conversa dispara evento. Vincular e desvincular
  # mudam o card sem tocar na conversa, entao o evento precisa sair daqui.
  describe 'announcing the conversation when the card is linked or unlinked' do
    let(:dispatched) { [Conversation::CONVERSATION_UPDATED, kind_of(Time)] }
    let(:payload) do
      { conversation: conversation, notifiable_assignee_change: false, changed_attributes: nil, performed_by: nil }
    end

    it 'announces the conversation as updated when a card is linked to it' do
      conversation
      task
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      described_class.create!(task: task, conversation: conversation)

      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(*dispatched, **payload)
    end

    it 'announces it again when the link is removed' do
      link = described_class.create!(task: task, conversation: conversation)
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      link.destroy!

      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(*dispatched, **payload)
    end

    # Mesmo recorte da fazer.ai Pro: mover o card nao re-dispara. O agente le a etapa ao vivo pela
    # API no preparo do turno, e re-disparar aqui colocaria o quadro inteiro dentro do caminho de
    # evento da conversa a cada arrastar de card.
    it 'stays quiet when the card only moves between steps' do
      described_class.create!(task: task, conversation: conversation)
      other_step = create(:funnel_step, board: board)
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      task.update!(step: other_step)

      expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)
        .with(Conversation::CONVERSATION_UPDATED, kind_of(Time), anything)
    end

    # A conversa destruida leva os vinculos junto. Anunciar atualizacao dela mandaria o consumidor
    # buscar o que nao existe mais.
    it 'stays quiet when the conversation itself is destroyed' do
      described_class.create!(task: task, conversation: conversation)
      allow(Rails.configuration.dispatcher).to receive(:dispatch)

      conversation.destroy!

      expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)
        .with(Conversation::CONVERSATION_UPDATED, kind_of(Time), anything)
    end
  end
end
