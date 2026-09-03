require 'rails_helper'

# Contrato externo, como o compat_spec ao lado: sao estas duas rotas que as ferramentas HTTP do
# agente Maria (projeto fazer.ai agents) chamam. Elas foram escritas contra a implementacao
# anterior do Kanban e nao mudam quando este fork muda, entao o que trava o contrato e este spec.
RSpec.describe 'Kanban conversation cards API', type: :request do
  let!(:account) { create(:account) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:board) { create(:funnel_board, account: account, name: 'Atendimento') }
  let!(:entry) { create(:funnel_step, board: board, name: 'Novo contato', stage_type: :open, rank: 100) }
  let!(:scheduled) { create(:funnel_step, board: board, name: 'Agendado', stage_type: :open, rank: 200) }
  let!(:administrator) { create(:user, account: account, role: :administrator) }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox) }

  let(:headers) { administrator.create_new_auth_token }
  let(:url) { "/api/v1/accounts/#{account.id}/kanban/conversation_cards/#{conversation.display_id}" }

  before { account.update!(funnel_kanban_enabled: true) }

  def link_card(step: entry)
    task = create(:funnel_task, board_for_task: board, step: step, title: 'Retorno')
    Funnel::TaskConversation.create!(task: task, conversation: conversation, is_primary: true)
    task
  end

  describe 'GET conversation_cards/:conversation_id' do
    it 'refuses an unauthenticated caller' do
      get url, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns the card with the names of the stage and of the board' do
      link_card

      get url, headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include(
        'stage_name' => 'Novo contato',
        'pipeline_name' => 'Atendimento',
        'valid_stages' => ['Novo contato', 'Agendado']
      )
    end

    # O agente distingue "ainda nao entrou no funil" de "entrou": um 200 vazio faria as duas
    # parecerem iguais, e a ferramenta dele ja declara 404 como resposta esperada.
    it 'answers not found when the conversation has no card' do
      get url, headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'ignores an archived card' do
      link_card.update!(archived_at: Time.current)

      get url, headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  # O ponto onde copiar a implementacao anterior teria plantado um bug: la a busca era pela chave
  # estrangeira conversation_id, que e a chave primaria global. O agente manda o display_id, que e
  # por conta. Enquanto os dois numeros coincidem — conta unica, nada apagado — os dois jeitos
  # passam; quando divergem, buscar pela chave primaria acha a conversa de outra pessoa.
  describe 'which conversation the id means' do
    it 'resolves by display_id and not by the primary key' do
      other = create(:conversation, account: account, inbox: inbox)
      # Escrita direta na coluna de proposito: display_id e preenchido por trigger no Postgres, e
      # o que este caso precisa e justamente um valor que nao coincida com a chave primaria — a
      # divergencia que so aparece em producao depois de conversas apagadas ou de outra conta.
      other.update_columns(display_id: conversation.id + 500) # rubocop:disable Rails/SkipsModelValidations
      task = create(:funnel_task, board_for_task: board, step: entry)
      Funnel::TaskConversation.create!(task: task, conversation: other, is_primary: true)

      get "/api/v1/accounts/#{account.id}/kanban/conversation_cards/#{other.display_id}",
          headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['id']).to eq(task.id)
    end

    it 'does not reach a conversation of another account' do
      stranger = create(:conversation, account: create(:account))

      get "/api/v1/accounts/#{account.id}/kanban/conversation_cards/#{stranger.display_id}",
          headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST conversation_cards/:conversation_id/move' do
    it 'moves the card to the stage named in the request' do
      task = link_card

      post "#{url}/move", params: { stage: 'Agendado' }, headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect(task.reload.funnel_step_id).to eq(scheduled.id)
      expect(response.parsed_body['stage_name']).to eq('Agendado')
    end

    # Um modelo que perde o acento ou a caixa ainda quer a mesma etapa; falhar ali faria o funil
    # parar de refletir a realidade sem ninguem notar.
    it 'matches the stage name without accents or case' do
      task = link_card(step: scheduled)

      post "#{url}/move", params: { stage: 'novo CONTATO' }, headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect(task.reload.step.name).to eq('Novo contato')
    end

    it 'answers an unknown stage with the list of valid ones' do
      link_card

      post "#{url}/move", params: { stage: 'Agendamento solicitado' }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['valid_stages']).to eq(['Novo contato', 'Agendado'])
      expect(response.parsed_body['error']).to include('Agendamento solicitado')
    end

    it 'answers a missing stage with the list of valid ones too' do
      link_card

      post "#{url}/move", params: {}, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['valid_stages']).to eq(['Novo contato', 'Agendado'])
    end

    # A etapa e procurada dentro do quadro do card, entao uma etapa de outro quadro nao e um nome
    # valido aqui — e o erro tem de dizer isso, nao mover o card para fora do quadro dele.
    it 'refuses a stage that belongs to another board' do
      link_card
      other_board = create(:funnel_board, account: account, name: 'Outro')
      create(:funnel_step, board: other_board, name: 'Etapa alheia', stage_type: :open, rank: 100)

      post "#{url}/move", params: { stage: 'Etapa alheia' }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'answers not found when the conversation has no card' do
      post "#{url}/move", params: { stage: 'Agendado' }, headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'the account feature switch' do
    it 'refuses when the module is off for the account' do
      account.update!(funnel_kanban_enabled: false)
      link_card

      get url, headers: headers, as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end
end
