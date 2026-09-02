class AddStepChangedAtToFunnelTasks < ActiveRecord::Migration[7.1]
  # "Tempo na etapa" e o dado que o card mostra em destaque, e derivar isso dos eventos custaria
  # uma varredura de funnel_task_events por card a cada desenho do quadro. Uma coluna paga a
  # leitura com uma escrita por movimento.
  def up
    add_column :funnel_tasks, :step_changed_at, :datetime

    # Card que nunca mudou de etapa esta nela desde que nasceu.
    execute <<~SQL.squish
      UPDATE funnel_tasks SET step_changed_at = created_at WHERE step_changed_at IS NULL
    SQL

    change_column_null :funnel_tasks, :step_changed_at, false
    add_index :funnel_tasks, [:funnel_step_id, :step_changed_at], name: 'idx_funnel_tasks_on_step_changed_at'
  end

  def down
    remove_index :funnel_tasks, name: 'idx_funnel_tasks_on_step_changed_at'
    remove_column :funnel_tasks, :step_changed_at
  end
end
