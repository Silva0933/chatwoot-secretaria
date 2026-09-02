require 'rails_helper'

RSpec.describe 'Funnel Boards API', type: :request do
  let!(:account) { create(:account) }
  let!(:administrator) { create(:user, account: account, role: :administrator) }
  let!(:agent) { create(:user, account: account, role: :agent) }

  let(:boards_path) { "/api/v1/accounts/#{account.id}/funnel/boards" }

  before { account.update!(funnel_kanban_enabled: true) }

  # Recusa de policy sai como 401 e nao 403: RequestExceptionHandler mapeia
  # Pundit::NotAuthorizedError para render_unauthorized. O 403 aqui e so o do toggle da conta,
  # que o proprio controller renderiza.

  describe 'GET index' do
    it 'returns unauthorized without authentication' do
      get boards_path

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns forbidden when the account does not have the feature' do
      account.update!(funnel_kanban_enabled: false)

      get boards_path, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'returns every active board of the account to an administrator' do
      board = create(:funnel_board, account: account)
      archived = create(:funnel_board, account: account, archived_at: Time.current)

      get boards_path, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      ids = response.parsed_body['payload'].pluck('id')
      expect(ids).to include(board.id)
      expect(ids).not_to include(archived.id)
    end

    it 'does not leak boards from another account' do
      other_board = create(:funnel_board, account: create(:account))

      get boards_path, headers: administrator.create_new_auth_token, as: :json

      expect(response.parsed_body['payload'].pluck('id')).not_to include(other_board.id)
    end

    it 'returns only the boards the agent is a member of' do
      member_board = create(:funnel_board, account: account)
      create(:funnel_board_member, board: member_board, user: agent)
      create(:funnel_board, account: account)

      get boards_path, headers: agent.create_new_auth_token, as: :json

      expect(response.parsed_body['payload'].pluck('id')).to contain_exactly(member_board.id)
    end
  end

  # A interface esconde acoes que a API recusaria, entao o payload precisa dizer o que este
  # usuario pode fazer neste quadro. Sem isso a unica fonte seria o 403 depois da tentativa.
  describe 'the permissions payload' do
    let!(:board) { create(:funnel_board, account: account) }

    def board_payload(user)
      get boards_path, headers: user.create_new_auth_token, as: :json
      response.parsed_body['payload'].find { |item| item['id'] == board.id }
    end

    it 'gives an administrator everything even without a membership' do
      payload = board_payload(administrator)

      expect(payload['current_user_role']).to be_nil
      expect(payload['permissions']).to eq(
        'manage_board' => true, 'manage_settings' => true, 'create_task' => true
      )
    end

    it 'lets a manager change the board settings but not archive the board' do
      create(:funnel_board_member, board: board, user: agent, role: :manager)

      payload = board_payload(agent)

      expect(payload['current_user_role']).to eq('manager')
      expect(payload['permissions']).to eq(
        'manage_board' => false, 'manage_settings' => true, 'create_task' => true
      )
    end

    it 'lets a member create cards only' do
      create(:funnel_board_member, board: board, user: agent, role: :member)

      payload = board_payload(agent)

      expect(payload['current_user_role']).to eq('member')
      expect(payload['permissions']).to eq(
        'manage_board' => false, 'manage_settings' => false, 'create_task' => true
      )
    end

    it 'gives a viewer no write permission at all' do
      create(:funnel_board_member, board: board, user: agent, role: :viewer)

      payload = board_payload(agent)

      expect(payload['current_user_role']).to eq('viewer')
      expect(payload['permissions']).to eq(
        'manage_board' => false, 'manage_settings' => false, 'create_task' => false
      )
    end

    it 'reports the permissions of the requesting user and not of another member' do
      create(:funnel_board_member, board: board, user: agent, role: :viewer)
      other_manager = create(:user, account: account, role: :agent)
      create(:funnel_board_member, board: board, user: other_manager, role: :manager)

      expect(board_payload(agent)['current_user_role']).to eq('viewer')
      expect(board_payload(other_manager)['current_user_role']).to eq('manager')
    end
  end

  describe 'GET show' do
    let!(:board) { create(:funnel_board, account: account) }

    it 'returns the board with its steps ordered by rank' do
      second = create(:funnel_step, board: board, name: 'Depois', rank: 200)
      first = create(:funnel_step, board: board, name: 'Antes', rank: 100)

      get "#{boards_path}/#{board.id}", headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['steps'].pluck('id')).to eq([first.id, second.id])
    end

    it 'returns not found for a board of another account' do
      other_board = create(:funnel_board, account: create(:account))

      get "#{boards_path}/#{other_board.id}", headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'denies an agent who is not a member of the board' do
      get "#{boards_path}/#{board.id}", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST create' do
    it 'creates the board with the clinic template and enrolls the creator as manager' do
      expect do
        post boards_path,
             params: { board: { name: 'Jornada do paciente' } },
             headers: administrator.create_new_auth_token,
             as: :json
      end.to change(Funnel::Board, :count).by(1)

      expect(response).to have_http_status(:success)
      board = Funnel::Board.find(response.parsed_body['id'])
      expect(board.steps.pluck(:name)).to eq(Funnel::Boards::CreateService::TEMPLATES[:clinic].pluck(:name))
      expect(board.members.find_by(user: administrator).role).to eq('manager')
    end

    it 'creates the board with the blank template when asked' do
      post boards_path,
           params: { board: { name: 'Simples' }, template: 'blank' },
           headers: administrator.create_new_auth_token,
           as: :json

      board = Funnel::Board.find(response.parsed_body['id'])
      expect(board.steps.pluck(:name)).to eq(Funnel::Boards::CreateService::TEMPLATES[:blank].pluck(:name))
    end

    it 'denies an agent creating a board' do
      expect do
        post boards_path,
             params: { board: { name: 'Meu quadro' } },
             headers: agent.create_new_auth_token,
             as: :json
      end.not_to change(Funnel::Board, :count)

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'PATCH update' do
    let!(:board) { create(:funnel_board, account: account, name: 'Antigo') }

    it 'renames the board for an administrator' do
      patch "#{boards_path}/#{board.id}",
            params: { board: { name: 'Novo' } },
            headers: administrator.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:success)
      expect(board.reload.name).to eq('Novo')
    end

    it 'denies a member renaming the board' do
      create(:funnel_board_member, board: board, user: agent, role: :member)

      patch "#{boards_path}/#{board.id}",
            params: { board: { name: 'Novo' } },
            headers: agent.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(board.reload.name).to eq('Antigo')
    end
  end

  describe 'DELETE destroy' do
    let!(:board) { create(:funnel_board, account: account) }

    # Arquiva em vez de excluir: o quadro carrega o historico de atendimento dos cards.
    it 'archives the board instead of deleting the row' do
      expect do
        delete "#{boards_path}/#{board.id}", headers: administrator.create_new_auth_token, as: :json
      end.not_to change(Funnel::Board, :count)

      expect(response).to have_http_status(:success)
      expect(board.reload.archived_at).to be_present
    end

    it 'denies a manager archiving the board' do
      create(:funnel_board_member, board: board, user: agent, role: :manager)

      delete "#{boards_path}/#{board.id}", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(board.reload.archived_at).to be_nil
    end
  end
end
