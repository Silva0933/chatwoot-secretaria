require 'rails_helper'

RSpec.describe 'Funnel Tasks API', type: :request do
  let!(:account) { create(:account) }
  let!(:board) { create(:funnel_board, account: account) }
  let!(:step) { create(:funnel_step, board: board) }
  let!(:administrator) { create(:user, account: account, role: :administrator) }
  let!(:agent) { create(:user, account: account, role: :agent) }

  before { account.update!(funnel_kanban_enabled: true) }

  let(:tasks_path) { "/api/v1/accounts/#{account.id}/funnel/boards/#{board.id}/tasks" }

  describe 'GET index' do
    it 'returns unauthorized without authentication' do
      get tasks_path

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns forbidden when the account does not have the feature' do
      account.update!(funnel_kanban_enabled: false)

      get tasks_path, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'returns the cards of the board to an administrator' do
      task = create(:funnel_task, board_for_task: board, step: step, title: 'Consulta de retorno')

      get tasks_path, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload'].pluck('id')).to include(task.id)
    end

    it 'hides cards from an agent who is not a member of the board' do
      create(:funnel_task, board_for_task: board, step: step)

      get tasks_path, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload']).to be_empty
    end

    context 'when the agent is a member limited to their own cards' do
      before { create(:funnel_board_member, board: board, user: agent, visibility_scope: :own_tasks) }

      it 'returns only the cards assigned to or created by them' do
        mine = create(:funnel_task, board_for_task: board, step: step, created_by: agent)
        assigned = create(:funnel_task, board_for_task: board, step: step)
        Funnel::TaskAssignee.create!(task: assigned, user: agent)
        someone_elses = create(:funnel_task, board_for_task: board, step: step)

        get tasks_path, headers: agent.create_new_auth_token, as: :json

        ids = response.parsed_body['payload'].pluck('id')
        expect(ids).to contain_exactly(mine.id, assigned.id)
        expect(ids).not_to include(someone_elses.id)
      end
    end
  end

  describe 'tenant isolation' do
    it 'refuses a board that belongs to another account' do
      foreign_board = create(:funnel_board, account: create(:account))

      get "/api/v1/accounts/#{account.id}/funnel/boards/#{foreign_board.id}/tasks",
          headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'refuses a user who does not belong to the account' do
      outsider = create(:user, account: create(:account), role: :administrator)

      get tasks_path, headers: outsider.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST create' do
    it 'creates a card and records who created it' do
      expect do
        post tasks_path, params: { task: { title: 'Primeira consulta', funnel_step_id: step.id } },
                   headers: administrator.create_new_auth_token, as: :json
      end.to change(Funnel::Task, :count).by(1)

      expect(response).to have_http_status(:success)
      expect(Funnel::Task.last.created_by).to eq(administrator)
    end

    it 'falls back to the entry step when none is given' do
      post tasks_path, params: { task: { title: 'Sem etapa' } },
                 headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(Funnel::Task.last.funnel_step_id).to eq(board.entry_step.id)
    end

    it 'forbids an agent who is not a member of the board' do
      post tasks_path, params: { task: { title: 'Nao permitido' } },
                 headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'PATCH move' do
    let!(:task) { create(:funnel_task, board_for_task: board, step: step) }
    let!(:target_step) { create(:funnel_step, board: board) }

    it 'moves the card to the given step' do
      patch "#{tasks_path}/#{task.id}/move", params: { step_id: target_step.id },
                                      headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(task.reload.funnel_step_id).to eq(target_step.id)
    end

    it 'refuses a step from another board' do
      foreign_step = create(:funnel_step, board: create(:funnel_board, account: account))

      patch "#{tasks_path}/#{task.id}/move", params: { step_id: foreign_step.id },
                                      headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'PATCH update' do
    let!(:task) { create(:funnel_task, board_for_task: board, step: step) }

    it 'reports a conflict when the card changed since it was loaded' do
      stale_version = task.lock_version
      task.update!(title: 'Alterado por outro agente')

      patch "#{tasks_path}/#{task.id}", params: { task: { title: 'Minha alteracao', lock_version: stale_version } },
                                 headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:conflict)
    end
  end

  describe 'DELETE destroy' do
    let!(:task) { create(:funnel_task, board_for_task: board, step: step) }

    it 'archives the card instead of deleting it' do
      expect do
        delete "#{tasks_path}/#{task.id}", headers: administrator.create_new_auth_token, as: :json
      end.not_to change(Funnel::Task, :count)

      expect(task.reload.archived_at).to be_present
    end
  end
end
