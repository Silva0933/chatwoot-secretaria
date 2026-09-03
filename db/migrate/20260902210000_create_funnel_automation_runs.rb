class CreateFunnelAutomationRuns < ActiveRecord::Migration[7.1]
  # O relatorio (4.10) pede que cada execucao guarde regra, evento de origem, acoes, resultado e
  # erro. Sem esse registro, automacao vira comportamento magico: o card se move sozinho e
  # ninguem consegue dizer por que.
  def change
    create_table :funnel_automation_runs do |t|
      t.bigint :account_id, null: false
      t.bigint :funnel_board_id, null: false
      t.bigint :funnel_task_id
      t.bigint :conversation_id
      t.string :rule, null: false
      t.string :event_name, null: false
      t.string :status, null: false, default: 'ok'
      t.jsonb :data, default: {}, null: false
      t.text :error
      t.datetime :created_at, null: false
    end

    add_index :funnel_automation_runs, [:account_id, :created_at], name: 'idx_funnel_automation_runs_on_account_created'
    add_index :funnel_automation_runs, [:funnel_board_id, :rule], name: 'idx_funnel_automation_runs_on_board_rule'
    add_index :funnel_automation_runs, :funnel_task_id, name: 'idx_funnel_automation_runs_on_task'
    add_foreign_key :funnel_automation_runs, :accounts, on_delete: :cascade
    add_foreign_key :funnel_automation_runs, :funnel_boards, on_delete: :cascade

    # As seis automacoes confirmadas sao booleanos por quadro. Em jsonb e nao em seis colunas
    # porque o conjunto ainda vai crescer, e cada nova automacao seria uma migration.
    add_column :funnel_boards, :automation_settings, :jsonb, default: {}, null: false
  end
end
