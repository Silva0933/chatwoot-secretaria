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

  def create_legacy_tables
    connection.create_table :kanban_pipelines do |t|
      t.bigint :account_id, null: false
      t.string :name, null: false
      t.text :description
      t.boolean :is_active, default: true, null: false
      t.integer :position, default: 0, null: false
      t.timestamps
    end
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
    connection.create_table :kanban_tasks do |t|
      t.bigint :account_id, null: false
      t.bigint :kanban_pipeline_id, null: false
      t.bigint :kanban_stage_id, null: false
      t.bigint :conversation_id
      t.bigint :contact_id, null: false
      t.bigint :assigned_agent_id
      t.bigint :inbox_id
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

  def drop_legacy_tables
    %i[kanban_tasks kanban_stages kanban_pipelines].each do |table|
      connection.drop_table(table, if_exists: true)
    end
  end

  def insert_legacy_fixture
    pipeline_id = connection.insert(
      "INSERT INTO kanban_pipelines (account_id, name, description, is_active, position, created_at, updated_at) " \
      "VALUES (#{account.id}, 'Venda de Sites', 'Do primeiro contato ao site fechado.', TRUE, 1, NOW(), NOW())"
    )
    stages = {
      novo: insert_stage(pipeline_id, 'Novo lead', 0, won: false, lost: false),
      ganho: insert_stage(pipeline_id, 'Ganho', 1, won: true, lost: false),
      perdido: insert_stage(pipeline_id, 'Perdido', 2, won: false, lost: true)
    }
    { pipeline_id: pipeline_id, stages: stages }
  end

  def insert_stage(pipeline_id, name, position, won:, lost:)
    connection.insert(
      'INSERT INTO kanban_stages ' \
      '(account_id, kanban_pipeline_id, name, position, is_won_stage, is_lost_stage, color_hex, created_at, updated_at) ' \
      "VALUES (#{account.id}, #{pipeline_id}, '#{name}', #{position}, #{won}, #{lost}, '#7C6FE0', NOW(), NOW())"
    )
  end

  def insert_task(stage_id, pipeline_id, overrides = {})
    values = {
      title: "'Marcos Pizzaria'", summary: 'NULL', priority: 2, conversation_id: conversation.id,
      assigned_agent_id: agent.id, value_cents: 125_050, loss_reason: 'NULL', metadata: %('{}'),
      due_date: 'NULL', position: 0
    }.merge(overrides)
    connection.insert(
      'INSERT INTO kanban_tasks ' \
      '(account_id, kanban_pipeline_id, kanban_stage_id, conversation_id, contact_id, assigned_agent_id, title, ' \
      'summary, priority, due_date, stage_entered_at, metadata, position, value_cents, loss_reason, ' \
      'created_at, updated_at) VALUES ' \
      "(#{account.id}, #{pipeline_id}, #{stage_id}, #{values[:conversation_id]}, #{contact.id}, " \
      "#{values[:assigned_agent_id]}, #{values[:title]}, #{values[:summary]}, #{values[:priority]}, " \
      "#{values[:due_date]}, NOW(), #{values[:metadata]}, #{values[:position]}, #{values[:value_cents]}, " \
      "#{values[:loss_reason]}, NOW(), NOW())"
    )
  end

  def run_migration
    ActiveRecord::Migration.suppress_messages { described_class.new.up }
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
    let!(:fixture) { create_legacy_tables && insert_legacy_fixture }

    after { drop_legacy_tables }

    it 'turns the pipeline into a board' do
      run_migration

      board = Funnel::Board.find_by(account_id: account.id)
      expect(board.name).to eq('Venda de Sites')
      expect(board.description).to eq('Do primeiro contato ao site fechado.')
      expect(board.archived_at).to be_nil
    end

    it 'keeps the stage order and marks won and lost' do
      run_migration

      steps = Funnel::Board.find_by(account_id: account.id).steps.order(:rank)
      expect(steps.map(&:name)).to eq(['Novo lead', 'Ganho', 'Perdido'])
      expect(steps.map(&:stage_type)).to eq(%w[open won lost])
    end

    # A etapa de ganho fecha por definicao; sem isso o funil ponderado do relatorio nasceria zerado.
    it 'gives the won stage a hundred percent chance of closing' do
      run_migration

      steps = Funnel::Board.find_by(account_id: account.id).steps
      expect(steps.find_by(name: 'Ganho').probability).to eq(100)
      expect(steps.find_by(name: 'Novo lead').probability).to eq(0)
    end

    it 'converts the card with its value in currency and not in cents' do
      insert_task(fixture[:stages][:novo], fixture[:pipeline_id])

      run_migration

      task = Funnel::Task.find_by(account_id: account.id)
      expect(task.title).to eq('Marcos Pizzaria')
      expect(task.value).to eq(BigDecimal('1250.50'))
      expect(task.priority).to eq('high')
    end

    # Zero era o default da coluna antiga, ou seja "ninguem preencheu" — nao "vale nada".
    it 'reports a card with no value as null instead of zero' do
      insert_task(fixture[:stages][:novo], fixture[:pipeline_id], value_cents: 0)

      run_migration

      expect(Funnel::Task.find_by(account_id: account.id).value).to be_nil
    end

    it 'links the card to its conversation, contact and agent' do
      insert_task(fixture[:stages][:novo], fixture[:pipeline_id])

      run_migration

      task = Funnel::Task.find_by(account_id: account.id)
      expect(task.conversations).to eq([conversation])
      expect(task.task_conversations.first.is_primary).to be true
      expect(task.contacts).to eq([contact])
      expect(task.assignees).to eq([agent])
    end

    # Uma conversa apagada depois que o card nasceu nao pode derrubar a importacao inteira.
    it 'imports the card even when the conversation is already gone' do
      insert_task(fixture[:stages][:novo], fixture[:pipeline_id], conversation_id: 'NULL')

      run_migration

      task = Funnel::Task.find_by(account_id: account.id)
      expect(task).to be_present
      expect(task.conversations).to be_empty
    end

    # loss_reason nao tem coluna aqui; some se nao for para o bag de atributos.
    it 'keeps the loss reason among the card attributes' do
      insert_task(fixture[:stages][:perdido], fixture[:pipeline_id],
                  loss_reason: "'Preco'", metadata: %('{"origem":"indicacao"}'))

      run_migration

      attributes = Funnel::Task.find_by(account_id: account.id).custom_attributes
      expect(attributes).to eq('origem' => 'indicacao', 'loss_reason' => 'Preco')
    end

    it 'does not duplicate anything when it runs twice' do
      insert_task(fixture[:stages][:novo], fixture[:pipeline_id])

      run_migration
      run_migration

      expect(Funnel::Board.count).to eq(1)
      expect(Funnel::Step.count).to eq(3)
      expect(Funnel::Task.count).to eq(1)
    end

    it 'undoes only what it imported' do
      insert_task(fixture[:stages][:novo], fixture[:pipeline_id])
      run_migration

      ActiveRecord::Migration.suppress_messages { described_class.new.down }

      expect(Funnel::Board.count).to eq(0)
      expect(Funnel::Task.count).to eq(0)
    end

    it 'archives a board whose pipeline was no longer active' do
      connection.update("UPDATE kanban_pipelines SET is_active = FALSE WHERE id = #{fixture[:pipeline_id]}")

      run_migration

      expect(Funnel::Board.find_by(account_id: account.id).archived_at).to be_present
    end
  end
end
