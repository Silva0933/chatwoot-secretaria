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
end
