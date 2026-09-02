require 'rails_helper'

RSpec.describe 'Funnel Task Associations API', type: :request do
  let!(:account) { create(:account) }
  let!(:board) { create(:funnel_board, account: account) }
  let!(:step) { create(:funnel_step, board: board) }
  let!(:task) { create(:funnel_task, board_for_task: board, step: step) }
  let!(:administrator) { create(:user, account: account, role: :administrator) }
  let!(:agent) { create(:user, account: account, role: :agent) }

  let(:task_path) { "/api/v1/accounts/#{account.id}/funnel/boards/#{board.id}/tasks/#{task.id}" }

  before { account.update!(funnel_kanban_enabled: true) }

  describe 'PUT assignees' do
    let!(:first) { create(:user, account: account, role: :agent) }
    let!(:second) { create(:user, account: account, role: :agent) }

    it 'replaces the whole set instead of appending' do
      put "#{task_path}/assignees", params: { user_ids: [first.id] }, headers: administrator.create_new_auth_token, as: :json
      expect(task.reload.assignees).to contain_exactly(first)

      put "#{task_path}/assignees", params: { user_ids: [second.id] }, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(task.reload.assignees).to contain_exactly(second)
      expect(response.parsed_body['assignees'].pluck('id')).to contain_exactly(second.id)
    end

    it 'clears the set when given an empty list' do
      Funnel::TaskAssignee.create!(task: task, user: first)

      put "#{task_path}/assignees", params: { user_ids: [] }, headers: administrator.create_new_auth_token, as: :json

      expect(task.reload.assignees).to be_empty
    end

    # Sem isso um agente de outra conta entraria como responsavel por um card que ele nem pode ver.
    it 'rejects a user from another account' do
      outsider = create(:user, account: create(:account), role: :agent)

      put "#{task_path}/assignees", params: { user_ids: [outsider.id] }, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(task.reload.assignees).to be_empty
    end

    it 'records one event carrying the ids before and after' do
      expect do
        put "#{task_path}/assignees", params: { user_ids: [first.id] }, headers: administrator.create_new_auth_token, as: :json
      end.to change { task.events.where(event_type: 'task.assignees_replaced').count }.by(1)

      event = task.events.find_by(event_type: 'task.assignees_replaced')
      expect(event.data_before['ids']).to eq([])
      expect(event.data_after['ids']).to eq([first.id])
      expect(event.actor).to eq(administrator)
    end

    # Uma gravacao que nao muda nada nao deve poluir o historico do card.
    it 'records no event when the set did not change' do
      Funnel::TaskAssignee.create!(task: task, user: first)

      expect do
        put "#{task_path}/assignees", params: { user_ids: [first.id] }, headers: administrator.create_new_auth_token, as: :json
      end.not_to change(Funnel::TaskEvent, :count)
    end

    # O vinculo intocado precisa sobreviver a troca, senao a ordem da lista na tela muda sozinha.
    it 'keeps the existing row when an id stays in the set' do
      Funnel::TaskAssignee.create!(task: task, user: first)
      untouched = task.task_assignees.find_by(user_id: first.id)

      put "#{task_path}/assignees", params: { user_ids: [first.id, second.id] }, headers: administrator.create_new_auth_token, as: :json

      expect(task.task_assignees.find_by(user_id: first.id).id).to eq(untouched.id)
    end
  end

  describe 'PUT labels' do
    let!(:label) { create(:label, account: account) }

    it 'replaces the labels of the card' do
      put "#{task_path}/labels", params: { label_ids: [label.id] }, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(task.reload.labels).to contain_exactly(label)
    end

    it 'rejects a label from another account' do
      outsider = create(:label, account: create(:account))

      put "#{task_path}/labels", params: { label_ids: [outsider.id] }, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(task.reload.labels).to be_empty
    end
  end

  describe 'PUT contacts' do
    let!(:contact) { create(:contact, account: account) }

    it 'replaces the contacts of the card' do
      put "#{task_path}/contacts", params: { contact_ids: [contact.id] }, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(task.reload.contacts).to contain_exactly(contact)
    end

    it 'rejects a contact from another account' do
      outsider = create(:contact, account: create(:account))

      put "#{task_path}/contacts", params: { contact_ids: [outsider.id] }, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(task.reload.contacts).to be_empty
    end
  end

  describe 'conversations' do
    let!(:conversation) { create(:conversation, account: account) }

    # O id na rota e o display_id, o numero que o agente ve no Chatwoot.
    it 'links a conversation by its display id' do
      post "#{task_path}/conversations", params: { conversation_id: conversation.display_id },
                                         headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(task.reload.conversations).to contain_exactly(conversation)
      expect(response.parsed_body['conversations'].first['id']).to eq(conversation.display_id)
    end

    it 'makes the first linked conversation the primary one without being asked' do
      post "#{task_path}/conversations", params: { conversation_id: conversation.display_id },
                                         headers: administrator.create_new_auth_token, as: :json

      expect(task.task_conversations.sole).to be_is_primary
    end

    it 'keeps a single primary when a second conversation is promoted' do
      other = create(:conversation, account: account)
      post "#{task_path}/conversations", params: { conversation_id: conversation.display_id },
                                         headers: administrator.create_new_auth_token, as: :json
      post "#{task_path}/conversations", params: { conversation_id: other.display_id },
                                         headers: administrator.create_new_auth_token, as: :json

      patch "#{task_path}/conversations/#{other.display_id}", headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(task.task_conversations.where(is_primary: true).pluck(:conversation_id)).to eq([other.id])
    end

    it 'unlinks a conversation' do
      post "#{task_path}/conversations", params: { conversation_id: conversation.display_id },
                                         headers: administrator.create_new_auth_token, as: :json

      delete "#{task_path}/conversations/#{conversation.display_id}", headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(task.reload.conversations).to be_empty
      expect(task.events.where(event_type: 'task.conversation_unlinked')).to be_present
    end

    # A regra do produto: a mesma conversa nao pode estar em dois cards ativos do mesmo quadro.
    it 'refuses a conversation already on another active card of the board' do
      other_task = create(:funnel_task, board_for_task: board, step: step)
      Funnel::Tasks::LinkConversationService.new(task: other_task, conversation: conversation).perform

      post "#{task_path}/conversations", params: { conversation_id: conversation.display_id },
                                         headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(task.reload.conversations).to be_empty
    end

    it 'allows the same conversation on a card of a different board' do
      other_board = create(:funnel_board, account: account)
      other_step = create(:funnel_step, board: other_board)
      other_task = create(:funnel_task, board_for_task: other_board, step: other_step)
      Funnel::Tasks::LinkConversationService.new(task: other_task, conversation: conversation).perform

      post "#{task_path}/conversations", params: { conversation_id: conversation.display_id },
                                         headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
    end

    it 'returns not found for a display id the account does not have' do
      post "#{task_path}/conversations", params: { conversation_id: 999_999 },
                                         headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    # display_id e numerado por conta, entao duas contas tem uma conversa 1. A busca precisa
    # resolver para a desta conta; sem o escopo, o mesmo numero alcancaria a conversa alheia.
    it 'resolves the display id inside the account and not across accounts' do
      other_account = create(:account)
      outsider = create(:conversation, account: other_account)

      post "#{task_path}/conversations", params: { conversation_id: outsider.display_id },
                                         headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(task.reload.conversations.pluck(:account_id)).to eq([account.id])
      expect(task.conversations).not_to include(outsider)
    end
  end

  describe 'GET events' do
    it 'returns the trail newest first' do
      Funnel::Tasks::ReplaceAssociationService.new(task: task, kind: :assignees, ids: [agent.id], actor: administrator).perform
      Funnel::Tasks::ReplaceAssociationService.new(task: task, kind: :assignees, ids: [], actor: administrator).perform

      get "#{task_path}/events", headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      payload = response.parsed_body['payload']
      expect(payload.pluck('event_type')).to all(eq('task.assignees_replaced'))
      expect(payload.first['actor']['name']).to eq(administrator.name)
      expect(Time.zone.parse(payload.first['created_at'])).to be >= Time.zone.parse(payload.last['created_at'])
    end
  end

  describe 'authorization' do
    # Recusa de policy sai como 401, ver RequestExceptionHandler.
    it 'denies an agent who is not a member of the board' do
      put "#{task_path}/assignees", params: { user_ids: [agent.id] }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'denies a viewer, who may read the card but not change it' do
      create(:funnel_board_member, board: board, user: agent, role: :viewer)

      put "#{task_path}/assignees", params: { user_ids: [agent.id] }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'lets a viewer read the event trail' do
      create(:funnel_board_member, board: board, user: agent, role: :viewer)

      get "#{task_path}/events", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
    end

    it 'returns forbidden when the account does not have the feature' do
      account.update!(funnel_kanban_enabled: false)

      put "#{task_path}/assignees", params: { user_ids: [] }, headers: administrator.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end
end
