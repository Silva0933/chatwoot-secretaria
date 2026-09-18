class AddPipelineValueToFunnel < ActiveRecord::Migration[7.1]
  # Valor ponderado do funil (relatorio 4.7): o card carrega o valor, a etapa carrega a
  # probabilidade de fechar, e o quadro carrega a moeda. Uma oportunidade de 10 mil numa etapa
  # de 40% pesa 4 mil no total ponderado.
  def change
    # ISO 4217 tem tres letras; guardar como string evita uma tabela de dominio para 180 valores
    # que nunca mudam.
    add_column :funnel_boards, :currency, :string, limit: 3, null: false, default: 'BRL'

    add_column :funnel_steps, :probability, :integer, null: false, default: 0

    # decimal e nao float: dinheiro em ponto flutuante acumula erro de arredondamento, e a soma
    # de um funil inteiro e exatamente onde isso aparece.
    add_column :funnel_tasks, :value, :decimal, precision: 15, scale: 2

    add_index :funnel_tasks, [:funnel_board_id, :value], name: 'idx_funnel_tasks_on_board_value'
  end
end
