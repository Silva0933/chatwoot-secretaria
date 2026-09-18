require 'rails_helper'

RSpec.describe 'Funnel Reports API', type: :request do
  let!(:account) { create(:account) }
  let!(:board) { create(:funnel_board, account: account, currency: 'BRL') }
  let!(:triage) { create(:funnel_step, board: board, name: 'Triagem', stage_type: :open, rank: 100, probability: 40) }
  let!(:scheduled) { create(:funnel_step, board: board, name: 'Agendado', stage_type: :open, rank: 200, probability: 80) }
  let!(:won_step) { create(:funnel_step, board: board, name: 'Compareceu', stage_type: :won, rank: 300) }
  let!(:lost_step) { create(:funnel_step, board: board, name: 'Faltou', stage_type: :lost, rank: 400) }
  let!(:administrator) { create(:user, account: account, role: :administrator) }
  let!(:agent) { create(:user, account: account, role: :agent) }

  let(:headers) { administrator.create_new_auth_token }
  let(:path) { "/api/v1/accounts/#{account.id}/funnel/boards/#{board.id}/report" }

  before { account.update!(funnel_kanban_enabled: true) }

  def report
    response.parsed_body['payload']
  end

  describe 'totals' do
    it 'counts what was created, won and lost in the period' do
      create(:funnel_task, board_for_task: board, step: triage)
      create(:funnel_task, board_for_task: board, step: won_step, step_changed_at: 2.days.ago)
      create(:funnel_task, board_for_task: board, step: lost_step, step_changed_at: 3.days.ago)

      get path, headers: headers, as: :json

      expect(response).to have_http_status(:success)
      expect(report['totals']).to include('created' => 3, 'won' => 1, 'lost' => 1)
    end

    # Taxa sobre o que fechou, nao sobre o total: incluir o que esta aberto afundaria o numero de
    # um funil saudavel so por ter muita coisa em andamento.
    it 'computes the win rate over what closed, ignoring open cards' do
      create_list(:funnel_task, 3, board_for_task: board, step: won_step, step_changed_at: 1.day.ago)
      create(:funnel_task, board_for_task: board, step: lost_step, step_changed_at: 1.day.ago)
      create_list(:funnel_task, 10, board_for_task: board, step: triage)

      get path, headers: headers, as: :json

      expect(report['totals']['win_rate']).to eq(75.0)
    end

    it 'leaves the win rate empty when nothing closed yet' do
      create(:funnel_task, board_for_task: board, step: triage)

      get path, headers: headers, as: :json

      expect(report['totals']['win_rate']).to be_nil
    end

    # Oportunidade de 1000 numa etapa de 40% pesa 400; de 1000 numa de 80% pesa 800.
    it 'weighs the open value by the probability of each stage' do
      create(:funnel_task, board_for_task: board, step: triage, value: 1000)
      create(:funnel_task, board_for_task: board, step: scheduled, value: 1000)

      get path, headers: headers, as: :json

      expect(report['totals']['open_value'].to_f).to eq(2000.0)
      expect(report['totals']['weighted_value'].to_f).to eq(1200.0)
    end

    it 'leaves out what closed before the period' do
      create(:funnel_task, board_for_task: board, step: won_step, step_changed_at: 90.days.ago)

      get path, headers: headers, as: :json

      expect(report['totals']['won']).to eq(0)
    end

    it 'honours an explicit period' do
      create(:funnel_task, board_for_task: board, step: won_step, step_changed_at: 60.days.ago)

      get "#{path}?since=#{70.days.ago.iso8601}", headers: headers, as: :json

      expect(report['totals']['won']).to eq(1)
    end
  end

  describe 'per stage' do
    it 'reports the count, the value and how many are stalled' do
      create(:funnel_task, board_for_task: board, step: triage, value: 500, step_changed_at: 20.days.ago)
      create(:funnel_task, board_for_task: board, step: triage, value: 300, step_changed_at: 1.hour.ago)

      get path, headers: headers, as: :json

      row = report['steps'].find { |step| step['name'] == 'Triagem' }
      expect(row).to include('count' => 2, 'stalled_count' => 1)
      expect(row['value'].to_f).to eq(800.0)
    end

    # Media seria distorcida por um unico card esquecido; a mediana descreve o caso tipico.
    it 'reports the median age and not the average' do
      create(:funnel_task, board_for_task: board, step: triage, step_changed_at: 1.day.ago)
      create(:funnel_task, board_for_task: board, step: triage, step_changed_at: 2.days.ago)
      create(:funnel_task, board_for_task: board, step: triage, step_changed_at: 300.days.ago)

      get path, headers: headers, as: :json

      row = report['steps'].find { |step| step['name'] == 'Triagem' }
      expect(row['median_age_seconds'] / 86_400).to eq(2)
    end
  end

  # A conversao sai da trilha de auditoria: o estado atual so diz onde os cards pararam, nao por
  # onde passaram.
  describe 'stage conversion' do
    it 'counts the moves between stages' do
      task = create(:funnel_task, board_for_task: board, step: triage)
      Funnel::Tasks::MoveService.new(task: task, step: scheduled, actor: administrator).perform
      other = create(:funnel_task, board_for_task: board, step: triage)
      Funnel::Tasks::MoveService.new(task: other, step: scheduled, actor: administrator).perform

      get path, headers: headers, as: :json

      row = report['transitions'].find { |item| item['from_step_id'] == triage.id }
      expect(row).to include('to_step_id' => scheduled.id, 'count' => 2)
    end

    it 'ignores a reorder inside the same stage' do
      task = create(:funnel_task, board_for_task: board, step: triage)
      Funnel::Tasks::MoveService.new(task: task, step: triage, actor: administrator).perform

      get path, headers: headers, as: :json

      expect(report['transitions']).to be_empty
    end
  end

  describe 'agents and stalled cards' do
    it 'ranks the agents by what they closed' do
      task = create(:funnel_task, board_for_task: board, step: won_step, step_changed_at: 1.day.ago, value: 900)
      Funnel::TaskAssignee.create!(task: task, user: agent)

      get path, headers: headers, as: :json

      row = report['agents'].find { |item| item['user_id'] == agent.id }
      expect(row).to include('won' => 1)
      expect(row['won_value'].to_f).to eq(900.0)
    end

    it 'lists the cards that have not moved in a week' do
      stuck = create(:funnel_task, board_for_task: board, step: triage, step_changed_at: 10.days.ago)
      create(:funnel_task, board_for_task: board, step: triage, step_changed_at: 1.hour.ago)

      get path, headers: headers, as: :json

      expect(report['stalled'].pluck('id')).to contain_exactly(stuck.id)
      expect(report['stalled'].first['days']).to eq(10)
    end
  end

  describe 'CSV export' do
    it 'sends a spreadsheet with the totals and one row per stage' do
      create(:funnel_task, board_for_task: board, step: triage, value: 500)

      get "#{path}.csv", headers: headers

      expect(response).to have_http_status(:success)
      expect(response.headers['Content-Type']).to include('text/csv')
      expect(response.body).to include('Quadro', board.name, 'Triagem')
    end
  end

  describe 'authorization' do
    # Um membro limitado aos proprios cards le um relatorio dos proprios cards, nao do quadro.
    it 'restricts the numbers to what the reader may see' do
      create(:funnel_board_member, board: board, user: agent, visibility_scope: :own_tasks)
      mine = create(:funnel_task, board_for_task: board, step: triage, created_by: agent)
      create(:funnel_task, board_for_task: board, step: triage)

      get path, headers: agent.create_new_auth_token, as: :json

      row = report['steps'].find { |step| step['id'] == triage.id }
      expect(row['count']).to eq(1)
      expect(mine.reload.created_by_id).to eq(agent.id)
    end

    it 'denies an agent who is not a member of the board' do
      get path, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end
end
