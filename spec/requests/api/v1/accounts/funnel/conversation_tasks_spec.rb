require 'rails_helper'

RSpec.describe 'Funnel Conversation Tasks API', type: :request do
  let!(:account) { create(:account) }
  let!(:board) { create(:funnel_board, account: account) }
  let!(:step) { create(:funnel_step, board: board, stage_type: :open) }
  let!(:conversation) { create(:conversation, account: account) }
  let!(:administrator) { create(:user, account: account, role: :administrator) }
  let!(:agent) { create(:user, account: account, role: :agent) }

  let(:path) { "/api/v1/accounts/#{account.id}/funnel/conversations/#{conversation.display_id}/tasks" }

  before { account.update!(funnel_kanban_enabled: true) }

  describe 'GET index' do
    it 'returns the active cards linked to the conversation' do
      task = create(:funnel_task, board_for_task: board, step: step)
      Funnel::Tasks::LinkConversationService.new(task: task, conversation: conversation).perform

      get path, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload'].pluck('id')).to contain_exactly(task.id)
    end

    # O painel da conversa nao tem colunas em volta para dizer onde o card esta.
    it 'names the board and the stage of each card' do
      task = create(:funnel_task, board_for_task: board, step: step)
      Funnel::Tasks::LinkConversationService.new(task: task, conversation: conversation).perform

      get path, headers: administrator.create_new_auth_token, as: :json

      payload = response.parsed_body['payload'].first
      expect(payload['board_name']).to eq(board.name)
      expect(payload['step_name']).to eq(step.name)
    end

    it 'leaves out a card that was archived' do
      task = create(:funnel_task, board_for_task: board, step: step)
      Funnel::Tasks::LinkConversationService.new(task: task, conversation: conversation).perform
      task.update!(archived_at: Time.current)

      get path, headers: administrator.create_new_auth_token, as: :json

      expect(response.parsed_body['payload']).to be_empty
    end

    it 'returns nothing for a conversation with no card' do
      get path, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload']).to be_empty
    end
  end

  describe 'POST create' do
    it 'creates a card on the board and links the conversation as primary' do
      expect do
        post path, params: { board_id: board.id }, headers: administrator.create_new_auth_token, as: :json
      end.to change(Funnel::Task, :count).by(1)

      expect(response).to have_http_status(:success)
      task = Funnel::Task.find(response.parsed_body['id'])
      expect(task.task_conversations.sole).to have_attributes(conversation_id: conversation.id, is_primary: true)
    end

    # Sem titulo, o nome de quem esta do outro lado diz mais do que "Nova tarefa": e por ele que
    # o atendente reconhece o card no quadro.
    it 'names the card after the contact when no title is given' do
      post path, params: { board_id: board.id }, headers: administrator.create_new_auth_token, as: :json

      expect(response.parsed_body['title']).to eq(conversation.contact.name)
    end

    it 'keeps a title that was given' do
      post path, params: { board_id: board.id, task: { title: 'Retorno de exame' } },
                 headers: administrator.create_new_auth_token, as: :json

      expect(response.parsed_body['title']).to eq('Retorno de exame')
    end

    it 'links the contact of the conversation to the card' do
      post path, params: { board_id: board.id }, headers: administrator.create_new_auth_token, as: :json

      task = Funnel::Task.find(response.parsed_body['id'])
      expect(task.contacts).to contain_exactly(conversation.contact)
    end

    it 'drops the card on the entry stage of the board' do
      create(:funnel_step, board: board, stage_type: :won, rank: 10)

      post path, params: { board_id: board.id }, headers: administrator.create_new_auth_token, as: :json

      expect(response.parsed_body['funnel_step_id']).to eq(board.entry_step.id)
    end

    it 'honours an explicit stage' do
      other = create(:funnel_step, board: board)

      post path, params: { board_id: board.id, funnel_step_id: other.id },
                 headers: administrator.create_new_auth_token, as: :json

      expect(response.parsed_body['funnel_step_id']).to eq(other.id)
    end

    # A regra do produto: um card ativo por conversa por quadro.
    it 'refuses a second card for the same conversation on the same board' do
      post path, params: { board_id: board.id }, headers: administrator.create_new_auth_token, as: :json

      expect do
        post path, params: { board_id: board.id }, headers: administrator.create_new_auth_token, as: :json
      end.not_to change(Funnel::Task, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'allows a card on a different board for the same conversation' do
      other_board = create(:funnel_board, account: account)
      create(:funnel_step, board: other_board)
      post path, params: { board_id: board.id }, headers: administrator.create_new_auth_token, as: :json

      post path, params: { board_id: other_board.id }, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
    end

    it 'returns not found for a board of another account' do
      outsider = create(:funnel_board, account: create(:account))

      post path, params: { board_id: outsider.id }, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'authorization' do
    it 'denies an agent who cannot create cards on the board' do
      create(:funnel_board_member, board: board, user: agent, role: :viewer)

      post path, params: { board_id: board.id }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns forbidden when the account does not have the feature' do
      account.update!(funnel_kanban_enabled: false)

      get path, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end
end
