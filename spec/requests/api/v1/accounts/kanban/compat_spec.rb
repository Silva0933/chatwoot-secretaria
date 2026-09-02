require 'rails_helper'

# Este spec guarda um contrato externo: o cliente Kanban do projeto fazer.ai agents
# (src/modules/chatwoot/client.ts + kanban.ts) fala com estas rotas e le estes campos. Quebrar
# qualquer nome aqui quebra o agente em producao, e nao ha teste do outro lado que avise.
RSpec.describe 'Kanban compatibility API', type: :request do
  let!(:account) { create(:account) }
  let!(:board) { create(:funnel_board, account: account, name: 'Pipeline') }
  let!(:step) { create(:funnel_step, board: board, name: 'Triagem', stage_type: :open, rank: 100) }
  let!(:lost_step) { create(:funnel_step, board: board, name: 'Perdido', stage_type: :lost, rank: 200) }
  let!(:administrator) { create(:user, account: account, role: :administrator) }

  let(:headers) { administrator.create_new_auth_token }
  let(:base) { "/api/v1/accounts/#{account.id}/kanban" }

  before { account.update!(funnel_kanban_enabled: true) }

  describe 'GET tasks' do
    it 'renders the card with the field names the agent reads' do
      task = create(:funnel_task, board_for_task: board, step: step, title: 'Retorno',
                                  description: 'trazer exame', priority: :high)

      get "#{base}/tasks/#{task.id}", headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include(
        'id' => task.id,
        'board_id' => board.id,
        'board_step_id' => step.id,
        'title' => 'Retorno',
        'description' => 'trazer exame',
        'priority' => 'high',
        'status' => 'open'
      )
      expect(response.parsed_body['board']).to include('id' => board.id, 'name' => 'Pipeline')
    end

    it 'reports the stage type as the status of the card' do
      task = create(:funnel_task, board_for_task: board, step: lost_step)

      get "#{base}/tasks/#{task.id}", headers: headers, as: :json

      expect(response.parsed_body['status']).to eq('lost')
    end

    it 'filters by board' do
      mine = create(:funnel_task, board_for_task: board, step: step)
      other_board = create(:funnel_board, account: account)
      create(:funnel_task, board_for_task: other_board, step: create(:funnel_step, board: other_board))

      get "#{base}/tasks?board_id=#{board.id}", headers: headers, as: :json

      expect(response.parsed_body['payload'].pluck('id')).to contain_exactly(mine.id)
    end
  end

  describe 'PATCH tasks' do
    let!(:task) { create(:funnel_task, board_for_task: board, step: step) }

    # start_date/due_date do contrato viram start_at/due_at aqui.
    it 'maps start_date and due_date onto the internal columns' do
      patch "#{base}/tasks/#{task.id}",
            params: { task: { start_date: '2026-04-01T10:00:00Z', due_date: '2026-04-05T10:00:00Z' } },
            headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect(task.reload.start_at).to be_present
      expect(task.due_at).to be_present
      expect(response.parsed_body['due_date']).to be_present
    end

    # No contrato da Pro as etiquetas sao texto; aqui sao registros de Label da conta.
    it 'turns label strings into account labels, creating what is missing' do
      existing = create(:label, account: account, title: 'urgente')

      expect do
        patch "#{base}/tasks/#{task.id}", params: { task: { labels: %w[urgente novo] } },
                                          headers: headers, as: :json
      end.to change(account.labels, :count).by(1)

      expect(task.reload.labels).to include(existing)
      expect(response.parsed_body['labels']).to contain_exactly('urgente', 'novo')
    end

    it 'replaces the label set instead of appending' do
      patch "#{base}/tasks/#{task.id}", params: { task: { labels: %w[alfa beta] } }, headers: headers, as: :json
      patch "#{base}/tasks/#{task.id}", params: { task: { labels: %w[beta] } }, headers: headers, as: :json

      expect(response.parsed_body['labels']).to contain_exactly('beta')
    end

    it 'leaves the labels alone when the key is absent' do
      patch "#{base}/tasks/#{task.id}", params: { task: { labels: %w[alfa] } }, headers: headers, as: :json

      patch "#{base}/tasks/#{task.id}", params: { task: { title: 'Outro' } }, headers: headers, as: :json

      expect(response.parsed_body['labels']).to contain_exactly('alfa')
    end

    # O agente manda texto livre, e o Chatwoot exige ao menos dois caracteres numa etiqueta.
    it 'names the label that Chatwoot refused instead of answering "Title is invalid"' do
      patch "#{base}/tasks/#{task.id}", params: { task: { labels: ['a'] } }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('"a"')
    end

    it 'assigns custom attributes' do
      patch "#{base}/tasks/#{task.id}", params: { task: { custom_attributes: { plano: 'ouro' } } },
                                        headers: headers, as: :json

      expect(response.parsed_body['custom_attributes']).to eq('plano' => 'ouro')
    end
  end

  describe 'POST tasks/:id/move' do
    it 'moves the card to the given board step' do
      task = create(:funnel_task, board_for_task: board, step: step)

      post "#{base}/tasks/#{task.id}/move", params: { board_step_id: lost_step.id },
                                            headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect(task.reload.funnel_step_id).to eq(lost_step.id)
    end

    # insert_before_task_id do contrato e o vizinho de baixo no nosso MoveService.
    it 'places the card before the given sibling' do
      first = create(:funnel_task, board_for_task: board, step: lost_step)
      moving = create(:funnel_task, board_for_task: board, step: step)

      post "#{base}/tasks/#{moving.id}/move",
           params: { board_step_id: lost_step.id, insert_before_task_id: first.id },
           headers: headers, as: :json

      ordered = Funnel::Task.where(funnel_step_id: lost_step.id).order(:rank).pluck(:id)
      expect(ordered).to eq([moving.id, first.id])
    end
  end

  describe 'POST tasks' do
    it 'creates a card on the board entry step' do
      post "#{base}/tasks", params: { task: { board_id: board.id, title: 'Novo lead' } },
                            headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include('title' => 'Novo lead', 'board_step_id' => board.entry_step.id)
    end
  end

  describe 'board steps' do
    it 'lists the steps with the cancelled flag the agent uses for lost buckets' do
      get "#{base}/boards/#{board.id}/steps", headers: headers, as: :json

      expect(response).to have_http_status(:success)
      payload = response.parsed_body['payload']
      expect(payload.pluck('name')).to eq(%w[Triagem Perdido])
      expect(payload.find { |item| item['name'] == 'Perdido' }['cancelled']).to be true
      expect(payload.find { |item| item['name'] == 'Triagem' }['cancelled']).to be false
    end
  end

  describe 'board membership' do
    it 'syncs inboxes as a set, removing what is not sent' do
      first = create(:inbox, account: account)
      second = create(:inbox, account: account)
      post "#{base}/boards/#{board.id}/update_inboxes", params: { inbox_ids: [first.id, second.id] },
                                                        headers: headers, as: :json

      post "#{base}/boards/#{board.id}/update_inboxes", params: { inbox_ids: [second.id] },
                                                        headers: headers, as: :json

      expect(response.parsed_body['inbox_ids']).to contain_exactly(second.id)
    end

    it 'syncs agents as a set' do
      agent = create(:user, account: account, role: :agent)

      post "#{base}/boards/#{board.id}/update_agents", params: { agent_ids: [agent.id] },
                                                       headers: headers, as: :json

      expect(response.parsed_body['agent_ids']).to include(agent.id)
    end
  end

  # O cliente do agente le o card direto do payload da conversa para poupar uma chamada.
  describe 'the conversation payload' do
    let!(:conversation) { create(:conversation, account: account) }

    it 'embeds the linked card under kanban_task' do
      task = create(:funnel_task, board_for_task: board, step: step, title: 'Do contato')
      Funnel::Tasks::LinkConversationService.new(task: task, conversation: conversation).perform

      get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}", headers: headers, as: :json

      expect(response.parsed_body['kanban_task']).to include('id' => task.id, 'title' => 'Do contato')
    end

    it 'sends kanban_task as null when there is no card' do
      get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}", headers: headers, as: :json

      expect(response.parsed_body).to have_key('kanban_task')
      expect(response.parsed_body['kanban_task']).to be_nil
    end

    # O partial do modulo vive sob custom/api/v1/... e nao sob api/v1/...: como custom/app/views
    # tem prioridade sobre app/views, um arquivo no mesmo caminho logico do core substituiria o
    # payload inteiro da conversa em vez de acrescentar um campo.
    it 'keeps every field of the core conversation payload' do
      get "/api/v1/accounts/#{account.id}/conversations/#{conversation.display_id}", headers: headers, as: :json

      expect(response.parsed_body).to include('id', 'messages', 'meta', 'status', 'inbox_id', 'account_id')
    end
  end

  describe 'authorization' do
    it 'returns forbidden when the account does not have the feature' do
      account.update!(funnel_kanban_enabled: false)

      get "#{base}/tasks", headers: headers, as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'does not leak a card from another account' do
      outsider = create(:funnel_task)

      get "#{base}/tasks/#{outsider.id}", headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
