require 'rails_helper'

RSpec.describe FunnelListener do
  let(:listener) { described_class.instance }
  let!(:account) { create(:account) }
  let!(:board) { create(:funnel_board, account: account) }
  let!(:step) { create(:funnel_step, board: board) }
  let!(:other_step) { create(:funnel_step, board: board) }
  let!(:administrator) { create(:user, account: account, role: :administrator) }
  let!(:member) { create(:user, account: account, role: :agent) }
  let!(:outsider) { create(:user, account: account, role: :agent) }

  before do
    account.update!(funnel_kanban_enabled: true)
    create(:funnel_board_member, board: board, user: member)
  end

  describe 'who receives the event' do
    let!(:task) { create(:funnel_task, board_for_task: board, step: step) }

    # Um agente que nao e membro do quadro nao ve os cards dele na API. Mandar o titulo pelo
    # websocket contornaria a policy pela porta dos fundos.
    it 'reaches the administrators and the board members, and nobody else' do
      expect(ActionCableBroadcastJob).to receive(:perform_later) do |tokens, _event, _payload|
        expect(tokens).to include(administrator.pubsub_token, member.pubsub_token)
        expect(tokens).not_to include(outsider.pubsub_token)
      end

      listener.funnel_task_updated(Events::Base.new('funnel.task.updated', Time.zone.now, task: task))
    end

    it 'sends the card payload with the account it belongs to' do
      expect(ActionCableBroadcastJob).to receive(:perform_later) do |_tokens, event_name, payload|
        expect(event_name).to eq('funnel.task.updated')
        expect(payload[:id]).to eq(task.id)
        expect(payload[:account_id]).to eq(account.id)
      end

      listener.funnel_task_updated(Events::Base.new('funnel.task.updated', Time.zone.now, task: task))
    end
  end

  # O disparo sai de callback do model, e nao de cada controller, para cobrir tambem o adaptador
  # /kanban e o agente. Estes casos guardam esse contrato.
  describe 'what the model dispatches' do
    it 'announces a card that was created' do
      expect(Rails.configuration.dispatcher).to receive(:dispatch)
        .with('funnel.task.created', anything, hash_including(:task))

      create(:funnel_task, board_for_task: board, step: step)
    end

    it 'tells a move apart from a plain edit' do
      task = create(:funnel_task, board_for_task: board, step: step)

      expect(Rails.configuration.dispatcher).to receive(:dispatch)
        .with('funnel.task.moved', anything, hash_including(:task))

      task.update!(funnel_step_id: other_step.id)
    end

    it 'reports an archived card as deleted, which is what the board must do with it' do
      task = create(:funnel_task, board_for_task: board, step: step)

      expect(Rails.configuration.dispatcher).to receive(:dispatch)
        .with('funnel.task.deleted', anything, hash_including(:task))

      task.update!(archived_at: Time.current)
    end

    it 'announces a plain edit as an update' do
      task = create(:funnel_task, board_for_task: board, step: step)

      expect(Rails.configuration.dispatcher).to receive(:dispatch)
        .with('funnel.task.updated', anything, hash_including(:task))

      task.update!(title: 'Outro titulo')
    end

    # Criar, renomear ou excluir coluna redesenha o quadro todo, entao a etapa nao tem evento
    # proprio: manda o quadro inteiro.
    it 'announces a board update when a stage changes' do
      expect(Rails.configuration.dispatcher).to receive(:dispatch)
        .with('funnel.board.updated', anything, hash_including(:board))

      step.update!(name: 'Renomeada')
    end
  end

  # O card desenha dados da conversa, e nenhum deles mexe no registro do card: sem estes dois
  # eventos o quadro aberto so se redesenhava quando alguem arrastava um card.
  describe 'keeping an open board in sync with the conversation' do
    let!(:inbox) { create(:inbox, account: account) }
    let!(:conversation) { create(:conversation, account: account, inbox: inbox) }
    let!(:task) { create(:funnel_task, board_for_task: board, step: step) }

    before { Funnel::TaskConversation.create!(task: task, conversation: conversation, is_primary: true) }

    it 'redraws the card when the customer writes' do
      message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming)

      expect(ActionCableBroadcastJob).to receive(:perform_later) do |_tokens, event_name, payload|
        expect(event_name).to eq('funnel.task.updated')
        expect(payload[:id]).to eq(task.id)
      end

      listener.message_created(Events::Base.new('message.created', Time.zone.now, message: message))
    end

    # A resposta do agente nao muda o trecho, que e a ultima mensagem DO CLIENTE. O que ela muda e
    # o waiting_since, e isso chega por conversation_updated ja assentado — Message grava o
    # waiting_since depois de despachar message.created.
    it 'ignores the agent reply, which changes nothing the card shows' do
      message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing)

      expect(ActionCableBroadcastJob).not_to receive(:perform_later)

      listener.message_created(Events::Base.new('message.created', Time.zone.now, message: message))
    end

    it 'redraws the card when the conversation changes' do
      expect(ActionCableBroadcastJob).to receive(:perform_later) do |_tokens, event_name, payload|
        expect(event_name).to eq('funnel.task.updated')
        expect(payload[:id]).to eq(task.id)
      end

      listener.conversation_updated(Events::Base.new('conversation.updated', Time.zone.now, conversation: conversation))
    end

    it 'stays quiet for a conversation no card is following' do
      loose = create(:conversation, account: account, inbox: inbox)

      expect(ActionCableBroadcastJob).not_to receive(:perform_later)

      listener.conversation_updated(Events::Base.new('conversation.updated', Time.zone.now, conversation: loose))
    end

    # Card arquivado ja saiu da tela. Reenvia-lo o traria de volta na proxima mensagem.
    it 'does not resurrect an archived card' do
      task.update!(archived_at: Time.current)

      expect(ActionCableBroadcastJob).not_to receive(:perform_later)

      listener.conversation_updated(Events::Base.new('conversation.updated', Time.zone.now, conversation: conversation))
    end
  end
end
