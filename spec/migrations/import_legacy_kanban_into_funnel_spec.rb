require 'rails_helper'
require Rails.root.join('db/migrate/20260918210000_import_legacy_kanban_into_funnel.rb')

# As tabelas kanban_* nao existem no schema deste repositorio: elas vieram do fork
# Silva0933/chatwoot e so estao no banco de quem rodou aquela versao. O spec as cria com a forma
# que aquele schema.rb declara, importa, e confere o outro lado.
RSpec.describe ImportLegacyKanbanIntoFunnel do
  let(:connection) { ActiveRecord::Base.connection }
  let!(:account) { create(:account) }
  let!(:contact) { create(:contact, account: account) }
  let!(:conversation) { create(:conversation, account: account, contact: contact) }
  let!(:agent) { create(:user, account: account, role: :agent) }

  def create_legacy_pipelines_table
    connection.create_table :kanban_pipelines do |t|
      t.bigint :account_id, null: false
      t.string :name, null: false
      t.text :description
      t.boolean :is_active, default: true, null: false
      t.integer :position, default: 0, null: false
      t.timestamps
    end
  end

  def create_legacy_stages_table
    connection.create_table :kanban_stages do |t|
      t.bigint :account_id, null: false
      t.bigint :kanban_pipeline_id, null: false
      t.string :name, null: false
      t.integer :position, default: 0, null: false
      t.boolean :is_won_stage, default: false, null: false
      t.boolean :is_lost_stage, default: false, null: false
      t.string :color_hex, default: '#4A86E8', null: false
      t.integer :wip_limit
      t.timestamps
    end
  end

  def create_legacy_tasks_table
    connection.create_table :kanban_tasks do |t|
      t.bigint :account_id, null: false
      t.bigint :kanban_pipeline_id, null: false
      t.bigint :kanban_stage_id, null: false
      t.bigint :conversation_id
      t.bigint :contact_id, null: false
      t.bigint :assigned_agent_id
      t.string :title, null: false
      t.integer :priority, default: 1, null: false
      t.datetime :due_date
      t.datetime :stage_entered_at, null: false
      t.jsonb :metadata, default: {}, null: false
      t.integer :position, default: 0, null: false
      t.bigint :value_cents, default: 0, null: false
      t.string :loss_reason
      t.string :summary
      t.timestamps
    end
  end

  def create_legacy_tables
    create_legacy_pipelines_table
    create_legacy_stages_table
    create_legacy_tasks_table
  end

  def drop_legacy_tables
    %i[kanban_tasks kanban_stages kanban_pipelines].each do |table|
      connection.drop_table(table, if_exists: true)
    end
  end

  def insert_pipeline
    connection.select_value(
      'INSERT INTO kanban_pipelines ' \
      '(account_id, name, description, is_active, position, created_at, updated_at) VALUES ' \
      "(#{account.id}, 'Venda de Sites', 'Do primeiro contato ao site fechado.', TRUE, 1, NOW(), NOW()) " \
      'RETURNING id'
    )
  end

  def insert_stage(pipeline_id, name, position, won: false, lost: false)
    connection.select_value(
      'INSERT INTO kanban_stages (account_id, kanban_pipeline_id, name, position, is_won_stage, ' \
      'is_lost_stage, color_hex, created_at, updated_at) VALUES ' \
      "(#{account.id}, #{pipeline_id}, '#{name}', #{position}, #{won}, #{lost}, '#7C6FE0', NOW(), NOW()) " \
      'RETURNING id'
    )
  end

  def insert_legacy_fixture
    pipeline_id = insert_pipeline
    {
      pipeline_id: pipeline_id,
      novo: insert_stage(pipeline_id, 'Novo lead', 0),
      ganho: insert_stage(pipeline_id, 'Ganho', 1, won: true),
      perdido: insert_stage(pipeline_id, 'Perdido', 2, lost: true)
    }
  end

  def task_defaults
    {
      title: "'Marcos Pizzaria'", summary: 'NULL', priority: 2, conversation_id: conversation.id,
      assigned_agent_id: agent.id, value_cents: 125_050, loss_reason: 'NULL',
      metadata: %('{}'), due_date: 'NULL', position: 0
    }
  end

  def insert_task(stage_id, overrides = {})
    v = task_defaults.merge(overrides)
    connection.select_value(
      'INSERT INTO kanban_tasks (account_id, kanban_pipeline_id, kanban_stage_id, conversation_id, ' \
      'contact_id, assigned_agent_id, title, summary, priority, due_date, stage_entered_at, metadata, ' \
      'position, value_cents, loss_reason, created_at, updated_at) VALUES ' \
      "(#{account.id}, #{fixture[:pipeline_id]}, #{stage_id}, #{v[:conversation_id]}, #{contact.id}, " \
      "#{v[:assigned_agent_id]}, #{v[:title]}, #{v[:summary]}, #{v[:priority]}, #{v[:due_date]}, NOW(), " \
      "#{v[:metadata]}, #{v[:position]}, #{v[:value_cents]}, #{v[:loss_reason]}, NOW(), NOW()) RETURNING id"
    )
  end

  def run_migration
    ActiveRecord::Migration.suppress_messages { described_class.new.up }
  end

  def board
    Funnel::Board.find_by(account_id: account.id)
  end

  def imported_task
    Funnel::Task.find_by(account_id: account.id)
  end

  # Sem as tabelas antigas nao ha nada a importar, e a migracao nao pode explodir: e exatamente a
  # situacao de toda instalacao nova deste fork.
  context 'when the legacy tables do not exist' do
    it 'does nothing and does not raise' do
      drop_legacy_tables

      expect { run_migration }.not_to raise_error
      expect(Funnel::Board.count).to eq(0)
    end
  end

  context 'when there is a legacy kanban to import' do
    before { create_legacy_tables }

    let!(:fixture) { insert_legacy_fixture }

    after { drop_legacy_tables }

    it 'turns the pipeline into a board' do
      run_migration

      expect(board.name).to eq('Venda de Sites')
      expect(board.description).to eq('Do primeiro contato ao site fechado.')
      expect(board.archived_at).to be_nil
    end

    it 'keeps the stage order and marks won and lost' do
      run_migration

      steps = board.steps.order(:rank)
      expect(steps.map(&:name)).to eq(['Novo lead', 'Ganho', 'Perdido'])
      expect(steps.map(&:stage_type)).to eq(%w[open won lost])
    end

    # A etapa de ganho fecha por definicao; sem isso o funil ponderado do relatorio nasceria zerado.
    it 'gives the won stage a hundred percent chance of closing' do
      run_migration

      expect(board.steps.find_by(name: 'Ganho').probability).to eq(100)
      expect(board.steps.find_by(name: 'Novo lead').probability).to eq(0)
    end

    it 'converts the card with its value in currency and not in cents' do
      insert_task(fixture[:novo])

      run_migration

      expect(imported_task.title).to eq('Marcos Pizzaria')
      expect(imported_task.value).to eq(BigDecimal('1250.50'))
      expect(imported_task.priority).to eq('high')
    end

    # Zero era o default da coluna antiga, ou seja "ninguem preencheu" — nao "vale nada".
    it 'reports a card with no value as null instead of zero' do
      insert_task(fixture[:novo], value_cents: 0)

      run_migration

      expect(imported_task.value).to be_nil
    end

    it 'links the card to its conversation, contact and agent' do
      insert_task(fixture[:novo])

      run_migration

      expect(imported_task.conversations).to eq([conversation])
      expect(imported_task.task_conversations.first.is_primary).to be true
      expect(imported_task.contacts).to eq([contact])
      expect(imported_task.assignees).to eq([agent])
    end

    # Uma conversa apagada depois que o card nasceu nao pode derrubar a importacao inteira.
    it 'imports the card even when the conversation is already gone' do
      insert_task(fixture[:novo], conversation_id: 'NULL')

      run_migration

      expect(imported_task).to be_present
      expect(imported_task.conversations).to be_empty
    end

    # loss_reason nao tem coluna aqui; some se nao for para o bag de atributos.
    it 'keeps the loss reason among the card attributes' do
      insert_task(fixture[:perdido], loss_reason: "'Preco'", metadata: %('{"origem":"indicacao"}'))

      run_migration

      expect(imported_task.custom_attributes).to eq('origem' => 'indicacao', 'loss_reason' => 'Preco')
    end

    it 'does not duplicate anything when it runs twice' do
      insert_task(fixture[:novo])

      run_migration
      run_migration

      expect(Funnel::Board.count).to eq(1)
      expect(Funnel::Step.count).to eq(3)
      expect(Funnel::Task.count).to eq(1)
    end

    it 'undoes only what it imported' do
      insert_task(fixture[:novo])
      run_migration

      ActiveRecord::Migration.suppress_messages { described_class.new.down }

      expect(Funnel::Board.count).to eq(0)
      expect(Funnel::Task.count).to eq(0)
    end

    # Converter o quadro e deixar o modulo desligado entregaria um funil que nao aparece no menu e
    # cuja API responde 403 — nem o operador nem o agente alcancariam o que foi importado.
    it 'turns the module on for the account that had a funnel' do
      expect(account.reload.funnel_kanban_enabled?).to be false

      run_migration

      expect(account.reload.funnel_kanban_enabled?).to be true
    end

    it 'leaves other accounts alone' do
      outsider = create(:account)

      run_migration

      expect(outsider.reload.funnel_kanban_enabled?).to be false
    end

    it 'archives a board whose pipeline was no longer active' do
      connection.execute("UPDATE kanban_pipelines SET is_active = FALSE WHERE id = #{fixture[:pipeline_id]}")

      run_migration

      expect(board.archived_at).to be_present
    end
  end
end
