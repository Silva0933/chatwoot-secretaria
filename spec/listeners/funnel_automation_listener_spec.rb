require 'rails_helper'

RSpec.describe FunnelAutomationListener do
  let(:listener) { described_class.instance }
  let!(:account) { create(:account) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:board) { create(:funnel_board, account: account) }
  let!(:entry) { create(:funnel_step, board: board, stage_type: :open, rank: 100) }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox) }

  # Se o gancho de registro nao resolver, nenhuma automacao roda e nada avisa: o quadro
  # simplesmente nunca reage. Este caso e o unico aviso que existe.
  it 'is registered on the async dispatcher' do
    expect(Rails.configuration.dispatcher.async_dispatcher.listeners).to include(described_class.instance)
  end

  # Ligar a caixa ao quadro e o gesto que diz "este funil atende este canal". Sem isso o quadro
  # nao deve receber nada automaticamente, senao toda conversa da conta cairia em todo funil.
  describe 'which boards react' do
    before { board.update!(automation_settings: { 'create_task_on_conversation' => true }) }

    it 'ignores a board with no inbox linked' do
      expect do
        listener.conversation_created(event_for('conversation.created'))
      end.not_to change(Funnel::Task, :count)
    end

    it 'acts on a board linked to the inbox of the conversation' do
      board.board_inboxes.create!(inbox_id: inbox.id)

      expect do
        listener.conversation_created(event_for('conversation.created'))
      end.to change(Funnel::Task, :count).by(1)

      expect(Funnel::Task.last.funnel_step_id).to eq(entry.id)
    end

    it 'ignores a board linked to another inbox' do
      board.board_inboxes.create!(inbox_id: create(:inbox, account: account).id)

      expect do
        listener.conversation_created(event_for('conversation.created'))
      end.not_to change(Funnel::Task, :count)
    end

    it 'ignores an archived board' do
      board.board_inboxes.create!(inbox_id: inbox.id)
      board.update!(archived_at: Time.current)

      expect do
        listener.conversation_created(event_for('conversation.created'))
      end.not_to change(Funnel::Task, :count)
    end
  end

  def event_for(name)
    Events::Base.new(name, Time.zone.now, conversation: conversation)
  end
end
