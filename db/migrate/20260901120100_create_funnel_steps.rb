class CreateFunnelSteps < ActiveRecord::Migration[7.1]
  def change
    create_table :funnel_steps do |t|
      t.references :funnel_board, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.text :description
      t.string :color, null: false, default: '#1f93ff'
      # Rank fracionario: mover um card e um UPDATE de uma linha, em vez de reescrever
      # a coluna inteira. Funnel::Ranking cuida da insercao por ponto medio e do rebalanceamento.
      t.decimal :rank, precision: 30, scale: 15, null: false
      t.integer :stage_type, null: false, default: 0

      t.timestamps
    end

    add_index :funnel_steps, [:funnel_board_id, :rank]
  end
end
