class CreateFunnelBoards < ActiveRecord::Migration[7.1]
  def change
    create_funnel_boards
    create_funnel_board_members
    create_funnel_board_inboxes
  end

  private

  def create_funnel_boards
    create_table :funnel_boards do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.text :description
      t.datetime :archived_at
      t.jsonb :settings, null: false, default: {}

      t.timestamps
    end

    add_index :funnel_boards, [:account_id, :archived_at]
  end

  # Papel e escopo de visibilidade vivem aqui, e nao em CustomRole: aquele modelo esta em
  # enterprise/ e sai da arvore quando gerarmos a imagem de revenda.
  def create_funnel_board_members
    create_table :funnel_board_members do |t|
      t.references :funnel_board, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.integer :role, null: false, default: 0
      t.integer :visibility_scope, null: false, default: 0

      t.timestamps
    end

    add_index :funnel_board_members, [:funnel_board_id, :user_id], unique: true, name: 'idx_funnel_board_members_unique'
  end

  def create_funnel_board_inboxes
    create_table :funnel_board_inboxes do |t|
      t.references :funnel_board, null: false, foreign_key: { on_delete: :cascade }
      t.references :inbox, null: false, foreign_key: { on_delete: :cascade }

      t.timestamps
    end

    add_index :funnel_board_inboxes, [:funnel_board_id, :inbox_id], unique: true, name: 'idx_funnel_board_inboxes_unique'
  end
end
