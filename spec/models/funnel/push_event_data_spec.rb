require 'rails_helper'

# O navegador recebe o card por duas portas: o JSON da API e o payload do websocket. Os dois
# alimentam o mesmo componente, entao um campo que exista so num deles vira card que aparece
# completo ao carregar e incompleto ao chegar por tempo real, ou o contrario. Nada no codigo
# liga os dois arquivos; este spec e essa ligacao.
RSpec.describe 'Funnel push event payloads', type: :request do
  let!(:account) { create(:account) }
  let!(:board) { create(:funnel_board, account: account) }
  let!(:step) { create(:funnel_step, board: board) }
  let!(:administrator) { create(:user, account: account, role: :administrator) }
  let!(:conversation) { create(:conversation, account: account) }
  let!(:task) { create(:funnel_task, board_for_task: board, step: step) }

  before do
    account.update!(funnel_kanban_enabled: true)
    Funnel::TaskAssignee.create!(task: task, user: administrator)
    Funnel::TaskLabel.create!(task: task, label: create(:label, account: account))
    Funnel::TaskContact.create!(task: task, contact: create(:contact, account: account))
    Funnel::Tasks::LinkConversationService.new(task: task, conversation: conversation).perform
  end

  it 'sends the same fields over the websocket as the API renders' do
    get "/api/v1/accounts/#{account.id}/funnel/boards/#{board.id}/tasks/#{task.id}",
        headers: administrator.create_new_auth_token, as: :json

    api_keys = response.parsed_body.keys.sort
    event_keys = task.reload.push_event_data.keys.map(&:to_s).sort

    expect(event_keys).to eq(api_keys)
  end

  # Chaves iguais nao bastam para estes dois: o quadro le o trecho em lote pelo controller e o
  # websocket le um card por vez pelo modelo. Sao dois caminhos ate a mesma frase, e um card que
  # mudasse de texto so por ter chegado por tempo real seria dificil de desconfiar.
  it 'excerpts the same customer message over both ports' do
    create(:message, account: account, inbox: conversation.inbox, conversation: conversation,
                     message_type: :incoming, content: 'Pode mandar a proposta')
    create(:message, account: account, inbox: conversation.inbox, conversation: conversation,
                     message_type: :outgoing, content: 'Ja estou preparando')

    get "/api/v1/accounts/#{account.id}/funnel/boards/#{board.id}/tasks/#{task.id}",
        headers: administrator.create_new_auth_token, as: :json

    expect(task.reload.push_event_data[:excerpt]).to eq('Pode mandar a proposta')
    expect(response.parsed_body['excerpt']).to eq('Pode mandar a proposta')
  end

  it 'describes the channel the same way in both' do
    get "/api/v1/accounts/#{account.id}/funnel/boards/#{board.id}/tasks/#{task.id}",
        headers: administrator.create_new_auth_token, as: :json

    api_channel = response.parsed_body['channel']
    event_channel = task.reload.push_event_data[:channel].transform_keys(&:to_s)

    expect(event_channel.keys.sort).to eq(api_channel.keys.sort)
    expect(event_channel['channel_type']).to eq(api_channel['channel_type'])
  end

  it 'carries the board with its steps when the board changes' do
    payload = board.push_event_data

    expect(payload[:id]).to eq(board.id)
    expect(payload[:steps].map { |item| item[:id] }).to eq(board.steps.ordered.pluck(:id))
  end
end
