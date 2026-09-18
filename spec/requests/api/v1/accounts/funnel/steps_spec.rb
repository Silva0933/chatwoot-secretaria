require 'rails_helper'

RSpec.describe 'Funnel Steps API', type: :request do
  let!(:account) { create(:account) }
  let!(:board) { create(:funnel_board, account: account) }
  let!(:first_step) { create(:funnel_step, board: board, name: 'Triagem', rank: 100) }
  let!(:second_step) { create(:funnel_step, board: board, name: 'Agendado', rank: 200) }
  let!(:administrator) { create(:user, account: account, role: :administrator) }
  let!(:agent) { create(:user, account: account, role: :agent) }

  let(:steps_path) { "/api/v1/accounts/#{account.id}/funnel/boards/#{board.id}/steps" }

  before { account.update!(funnel_kanban_enabled: true) }

  describe 'POST create' do
    it 'adds a stage to the board' do
      post steps_path,
           params: { step: { name: 'Aguardando exame', color: '#3b82f6', stage_type: 'open' } },
           headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(board.steps.pluck(:name)).to include('Aguardando exame')
      expect(response.parsed_body['steps'].pluck('name')).to include('Aguardando exame')
    end

    it 'rejects an invalid colour' do
      post steps_path, params: { step: { name: 'X', color: 'azul' } },
                       headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe 'PATCH update' do
    it 'renames and recolours a stage' do
      patch "#{steps_path}/#{first_step.id}",
            params: { step: { name: 'Triagem inicial', color: '#10b981' } },
            headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(first_step.reload).to have_attributes(name: 'Triagem inicial', color: '#10b981')
    end

    it 'changes the stage type' do
      patch "#{steps_path}/#{first_step.id}", params: { step: { stage_type: 'won' } },
                                              headers: administrator.create_new_auth_token, as: :json

      expect(first_step.reload).to be_stage_won
    end
  end

  describe 'DELETE destroy' do
    it 'deletes an empty stage' do
      delete "#{steps_path}/#{second_step.id}", headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(board.steps.pluck(:id)).to contain_exactly(first_step.id)
    end

    # A associacao e restrict_with_error: sem realocar, a exclusao levaria junto o historico de
    # atendimento de cada card, ou simplesmente falharia sem explicar.
    it 'moves the cards to the chosen stage before deleting' do
      task = create(:funnel_task, board_for_task: board, step: first_step)

      delete "#{steps_path}/#{first_step.id}", params: { target_step_id: second_step.id },
                                               headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(task.reload.funnel_step_id).to eq(second_step.id)
      expect(Funnel::Step.exists?(first_step.id)).to be false
    end

    it 'falls back to the first remaining stage when none is chosen' do
      task = create(:funnel_task, board_for_task: board, step: second_step)

      delete "#{steps_path}/#{second_step.id}", headers: administrator.create_new_auth_token, as: :json

      expect(task.reload.funnel_step_id).to eq(first_step.id)
    end

    it 'refuses to delete the last stage of a board' do
      delete "#{steps_path}/#{second_step.id}", headers: administrator.create_new_auth_token, as: :json

      delete "#{steps_path}/#{first_step.id}", headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(board.reload.steps.count).to eq(1)
    end
  end

  describe 'PATCH reorder' do
    it 'applies the order given by the client' do
      patch "#{steps_path}/reorder", params: { step_ids: [second_step.id, first_step.id] },
                                     headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(board.steps.ordered.pluck(:id)).to eq([second_step.id, first_step.id])
    end

    it 'refuses an order that names a stage of another board' do
      outsider = create(:funnel_step, board: create(:funnel_board, account: account))

      patch "#{steps_path}/reorder", params: { step_ids: [first_step.id, outsider.id] },
                                     headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(board.steps.ordered.pluck(:id)).to eq([first_step.id, second_step.id])
    end
  end

  describe 'authorization' do
    # Mexer nas colunas muda o funil para todos, entao pede manage_settings? e nao update?.
    it 'denies a plain member of the board' do
      create(:funnel_board_member, board: board, user: agent, role: :member)

      post steps_path, params: { step: { name: 'X' } }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'allows a manager of the board' do
      create(:funnel_board_member, board: board, user: agent, role: :manager)

      post steps_path, params: { step: { name: 'Nova' } }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
    end
  end
end
