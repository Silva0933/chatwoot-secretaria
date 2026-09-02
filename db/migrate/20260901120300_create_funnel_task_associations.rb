class CreateFunnelTaskAssociations < ActiveRecord::Migration[7.1]
  def change
    create_funnel_task_conversations
    create_funnel_task_contacts
    create_funnel_task_assignees
    create_funnel_task_labels
  end

  private

  # funnel_board_id e active sao copias controladas de funnel_tasks. Existem porque o Postgres nao
  # aplica unique index parcial atravessando tabelas, e e esse index que garante a regra do
  # produto: uma conversa nunca aparece em dois cards ativos do mesmo quadro. Sem ele, a
  # automacao "nova conversa cria card" duplicaria em qualquer corrida. Funnel::TaskConversation
  # mantem as duas colunas em sincronia com o card.
  def create_funnel_task_conversations
    create_table :funnel_task_conversations do |t|
      t.references :funnel_task, null: false, foreign_key: { on_delete: :cascade }
      t.references :conversation, null: false, foreign_key: { on_delete: :cascade }
      t.bigint :funnel_board_id, null: false
      t.boolean :is_primary, null: false, default: false
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :funnel_task_conversations, [:funnel_task_id, :conversation_id], unique: true,
                                                                         name: 'idx_funnel_task_conversations_unique'
    add_index :funnel_task_conversations, [:funnel_board_id, :conversation_id], unique: true, where: 'active',
                                                                         name: 'idx_funnel_task_conversations_one_active_per_board'
    add_index :funnel_task_conversations, :funnel_task_id, unique: true, where: 'is_primary',
                                                     name: 'idx_funnel_task_conversations_one_primary'
  end

  def create_funnel_task_contacts
    create_table :funnel_task_contacts do |t|
      t.references :funnel_task, null: false, foreign_key: { on_delete: :cascade }
      t.references :contact, null: false, foreign_key: { on_delete: :cascade }

      t.timestamps
    end

    add_index :funnel_task_contacts, [:funnel_task_id, :contact_id], unique: true, name: 'idx_funnel_task_contacts_unique'
  end

  def create_funnel_task_assignees
    create_table :funnel_task_assignees do |t|
      t.references :funnel_task, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, null: false, foreign_key: { on_delete: :cascade }

      t.timestamps
    end

    add_index :funnel_task_assignees, [:funnel_task_id, :user_id], unique: true, name: 'idx_funnel_task_assignees_unique'
  end

  def create_funnel_task_labels
    create_table :funnel_task_labels do |t|
      t.references :funnel_task, null: false, foreign_key: { on_delete: :cascade }
      t.references :label, null: false, foreign_key: { on_delete: :cascade }

      t.timestamps
    end

    add_index :funnel_task_labels, [:funnel_task_id, :label_id], unique: true, name: 'idx_funnel_task_labels_unique'
  end
end
