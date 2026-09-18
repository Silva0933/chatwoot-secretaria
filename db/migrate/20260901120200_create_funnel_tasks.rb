class CreateFunnelTasks < ActiveRecord::Migration[7.1]
  def change
    create_funnel_tasks
    add_funnel_task_indexes
  end

  private

  def create_funnel_tasks
    create_table :funnel_tasks do |t|
      # account_id e desnormalizado de proposito: toda consulta do modulo filtra por tenant
      # sem precisar de join com funnel_boards.
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :funnel_board, null: false, foreign_key: { on_delete: :cascade }
      t.references :funnel_step, null: false, foreign_key: { on_delete: :restrict }
      t.bigint :created_by_id

      t.string :title, null: false
      t.text :description
      # Mesma escala de Conversation#priority (low/medium/high/urgent, nil = nenhuma),
      # para que a sincronizacao com a conversa na Fase 3 seja copia direta.
      t.integer :priority
      t.decimal :rank, precision: 30, scale: 15, null: false
      t.datetime :start_at
      t.datetime :due_at
      t.datetime :archived_at
      t.jsonb :custom_attributes, null: false, default: {}
      t.integer :lock_version, null: false, default: 0

      t.timestamps
    end
  end

  def add_funnel_task_indexes
    add_index :funnel_tasks, [:funnel_board_id, :funnel_step_id, :rank], name: 'idx_funnel_tasks_on_board_step_rank'
    add_index :funnel_tasks, [:funnel_board_id, :due_at], name: 'idx_funnel_tasks_on_board_due_at'
    add_index :funnel_tasks, [:funnel_board_id, :priority], name: 'idx_funnel_tasks_on_board_priority'
    add_index :funnel_tasks, [:account_id, :archived_at], name: 'idx_funnel_tasks_on_account_archived_at'
    add_index :funnel_tasks, :created_by_id
    add_index :funnel_tasks, :custom_attributes, using: :gin
  end
end
