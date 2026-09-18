require 'rails_helper'

RSpec.describe 'Funnel Board Settings API', type: :request do
  let!(:account) { create(:account) }
  let!(:board) { create(:funnel_board, account: account) }
  let!(:step) { create(:funnel_step, board: board) }
  let!(:administrator) { create(:user, account: account, role: :administrator) }
  let!(:agent) { create(:user, account: account, role: :agent) }

  let(:headers) { administrator.create_new_auth_token }
  let(:board_path) { "/api/v1/accounts/#{account.id}/funnel/boards/#{board.id}" }

  before { account.update!(funnel_kanban_enabled: true) }

  describe 'PUT members' do
    it 'sets the members with their role and visibility scope' do
      put "#{board_path}/members",
          params: { members: [{ user_id: agent.id, role: 'manager', visibility_scope: 'own_tasks' }] },
          headers: headers, as: :json

      expect(response).to have_http_status(:success)
      member = board.members.sole
      expect(member).to have_attributes(user_id: agent.id, role: 'manager', visibility_scope: 'own_tasks')
    end

    it 'removes whoever is left out of the list' do
      create(:funnel_board_member, board: board, user: agent)

      put "#{board_path}/members", params: { members: [] }, headers: headers, as: :json

      expect(board.reload.members).to be_empty
    end

    # Recriar a linha perderia o papel de quem nao foi tocado.
    it 'keeps the row of a member who stayed' do
      create(:funnel_board_member, board: board, user: agent, role: :manager)
      untouched = board.members.sole

      other = create(:user, account: account, role: :agent)
      put "#{board_path}/members",
          params: { members: [{ user_id: agent.id }, { user_id: other.id }] },
          headers: headers, as: :json

      expect(board.members.find_by(user_id: agent.id).id).to eq(untouched.id)
      expect(board.members.find_by(user_id: agent.id).role).to eq('manager')
    end

    it 'answers with the board so the caller sees the new permissions' do
      put "#{board_path}/members", params: { members: [{ user_id: agent.id }] }, headers: headers, as: :json

      expect(response.parsed_body['members'].pluck('user_id')).to contain_exactly(agent.id)
    end

    it 'denies a plain member of the board' do
      create(:funnel_board_member, board: board, user: agent, role: :member)

      put "#{board_path}/members", params: { members: [] }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'PUT inboxes' do
    let!(:inbox) { create(:inbox, account: account) }

    it 'links the inboxes to the board' do
      put "#{board_path}/inboxes", params: { inbox_ids: [inbox.id] }, headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect(board.reload.board_inboxes.pluck(:inbox_id)).to contain_exactly(inbox.id)
    end

    # O id vem do cliente, e o quadro so pode apontar para o que a propria conta enxerga.
    it 'ignores an inbox from another account' do
      outsider = create(:inbox, account: create(:account))

      put "#{board_path}/inboxes", params: { inbox_ids: [inbox.id, outsider.id] }, headers: headers, as: :json

      expect(board.reload.board_inboxes.pluck(:inbox_id)).to contain_exactly(inbox.id)
    end

    it 'unlinks what is left out' do
      board.board_inboxes.create!(inbox_id: inbox.id)

      put "#{board_path}/inboxes", params: { inbox_ids: [] }, headers: headers, as: :json

      expect(board.reload.board_inboxes).to be_empty
    end
  end

  # As automacoes sao o que faz o quadro reagir sozinho, e nao havia teste nenhum sobre gravar
  # esses interruptores. Sem isso, um quadro sem automacao nenhuma parece configurado.
  describe 'PATCH automation_settings' do
    it 'stores the switches that were turned on' do
      patch board_path,
            params: { board: { automation_settings: { 'create_task_on_conversation' => true,
                                                      'resolve_conversation_on_final_step' => true } } },
            headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect(board.reload.automation_settings).to include(
        'create_task_on_conversation' => true,
        'resolve_conversation_on_final_step' => true
      )
    end

    it 'answers with the switches so the screen can render what was saved' do
      patch board_path,
            params: { board: { automation_settings: { 'create_task_on_conversation' => true } } },
            headers: headers, as: :json

      expect(response.parsed_body.dig('payload', 'automation_settings') ||
             response.parsed_body['automation_settings']).to include('create_task_on_conversation' => true)
    end

    # Nome que nao e uma regra conhecida nao pode entrar: o motor ignoraria, e o quadro ficaria
    # afirmando na tela uma automacao que nunca roda.
    it 'drops a switch that is not a known rule' do
      patch board_path,
            params: { board: { automation_settings: { 'drop_database' => true } } },
            headers: headers, as: :json

      expect(board.reload.automation_settings).not_to have_key('drop_database')
    end

    it 'keeps the switches when another field of the board is edited' do
      board.update!(automation_settings: { 'create_task_on_conversation' => true })

      patch board_path, params: { board: { name: 'Outro nome' } }, headers: headers, as: :json

      expect(board.reload.automation_settings).to include('create_task_on_conversation' => true)
    end
  end

  describe 'the weighted pipeline' do
    it 'carries the currency of the board and the probability of each stage' do
      board.update!(currency: 'EUR')
      step.update!(probability: 40)

      get board_path, headers: headers, as: :json

      expect(response.parsed_body['currency']).to eq('EUR')
      expect(response.parsed_body['steps'].first['probability']).to eq(40)
    end

    it 'rejects a probability outside 0..100' do
      patch "#{board_path}/steps/#{step.id}", params: { step: { probability: 140 } }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'rejects a currency that is not a 3-letter code' do
      patch board_path, params: { board: { name: board.name, currency: 'reais' } }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    # String e nao numero: decimal(15,2) em JSON viraria float, e centavo somado em float erra.
    it 'sends the card value as a string' do
      task = create(:funnel_task, board_for_task: board, step: step, value: 1500.5)

      get "#{board_path}/tasks/#{task.id}", headers: headers, as: :json

      expect(response.parsed_body['value']).to eq('1500.5')
    end

    it 'refuses a negative value' do
      task = create(:funnel_task, board_for_task: board, step: step)

      patch "#{board_path}/tasks/#{task.id}", params: { task: { value: -10 } }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
