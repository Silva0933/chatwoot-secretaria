class CreateFunnelTaskEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :funnel_task_events do |t|
      t.references :funnel_task, null: false, foreign_key: { on_delete: :cascade }
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.bigint :actor_id
      t.string :actor_type
      t.string :event_type, null: false
      # De onde veio a mudanca: web, api, automation, system. Junto do correlation_id, e o que
      # permite a Fase 3 espelhar mudancas entre card e conversa sem entrar em loop.
      t.string :source, null: false, default: 'web'
      t.uuid :correlation_id
      t.jsonb :data_before, null: false, default: {}
      t.jsonb :data_after, null: false, default: {}

      t.datetime :created_at, null: false
    end

    add_index :funnel_task_events, [:funnel_task_id, :created_at]
    add_index :funnel_task_events, [:actor_type, :actor_id]
    add_index :funnel_task_events, :correlation_id, where: 'correlation_id IS NOT NULL'
  end
end
