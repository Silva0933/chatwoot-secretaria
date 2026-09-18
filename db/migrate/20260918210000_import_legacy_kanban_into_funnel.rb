class ImportLegacyKanbanIntoFunnel < ActiveRecord::Migration[7.1]
  # Migracao de DADOS, nao de estrutura: converte o Kanban antigo (kanban_pipelines / kanban_stages /
  # kanban_tasks, que veio do fork Silva0933/chatwoot) para o modulo Funnel deste repositorio.
  #
  # Nao apaga nada do antigo. As tabelas kanban_* continuam no banco depois disto; se a conversao
  # sair torta, o original esta la para reimportar. Descarta-las e decisao de outra migracao, depois
  # que o funil novo estiver em uso de verdade.
  #
  # Idempotente: o quadro criado guarda o id do pipeline de origem em settings, e um pipeline ja
  # importado e pulado. Rodar duas vezes nao duplica.
  #
  # Instalacao nova nao tem as tabelas antigas e sai na primeira linha.
  #
  # SQL direto, e nao os modelos Funnel::*, por dois motivos: um modelo muda com o tempo e levaria
  # esta migracao junto, e os callbacks de Funnel::Task disparam um evento por card gravado —
  # importar um funil inteiro encheria a fila de eventos de cards que ninguem moveu.

  LEGACY_KEY = 'legacy_kanban_pipeline_id'.freeze

  def up
    return unless table_exists?(:kanban_pipelines)

    legacy_pipelines.each do |pipeline|
      next if already_imported?(pipeline['id'])

      board_id = insert_board(pipeline)
      insert_tasks(pipeline['id'], board_id, insert_steps(pipeline['id'], board_id))
    end
  end

  def down
    return unless table_exists?(:funnel_boards)

    ids = select_values("SELECT id FROM funnel_boards WHERE settings->>'#{LEGACY_KEY}' IS NOT NULL")
    return if ids.empty?

    # Nesta ordem: funnel_tasks referencia funnel_steps com on_delete restrict, entao apagar o
    # quadro primeiro deixaria o cascade das etapas esbarrar nos cards.
    list = ids.join(',')
    execute("DELETE FROM funnel_tasks WHERE funnel_board_id IN (#{list})")
    execute("DELETE FROM funnel_steps WHERE funnel_board_id IN (#{list})")
    execute("DELETE FROM funnel_boards WHERE id IN (#{list})")
  end

  private

  def legacy_pipelines
    select_all(<<~SQL.squish).to_a
      SELECT id, account_id, name, description, is_active, created_at, updated_at
      FROM kanban_pipelines ORDER BY position, id
    SQL
  end

  def already_imported?(pipeline_id)
    select_value(
      "SELECT 1 FROM funnel_boards WHERE settings->>'#{LEGACY_KEY}' = #{quote(pipeline_id.to_s)} LIMIT 1"
    ).present?
  end

  # Pipeline inativo vira quadro arquivado: e o que as duas bases chamam de "sumiu da tela sem
  # perder o historico".
  def insert_board(pipeline)
    archived = pipeline['is_active'] ? 'NULL' : quote(pipeline['updated_at'])
    select_value(<<~SQL.squish)
      INSERT INTO funnel_boards
        (account_id, name, description, archived_at, settings, currency, automation_settings,
         created_at, updated_at)
      VALUES
        (#{quote(pipeline['account_id'])}, #{quote(pipeline['name'])}, #{quote(pipeline['description'])},
         #{archived}, #{quote({ LEGACY_KEY => pipeline['id'] }.to_json)}, 'BRL', '{}',
         #{quote(pipeline['created_at'])}, #{quote(pipeline['updated_at'])})
      RETURNING id
    SQL
  end

  # Devolve o de-para stage antigo -> etapa nova, que insert_tasks usa para achar a coluna do card.
  def insert_steps(pipeline_id, board_id)
    mapping = {}
    legacy_stages(pipeline_id).each_with_index do |stage, index|
      mapping[stage['id']] = insert_step(board_id, stage, index)
    end
    mapping
  end

  def legacy_stages(pipeline_id)
    select_all(<<~SQL.squish).to_a
      SELECT id, name, position, is_won_stage, is_lost_stage, color_hex, created_at, updated_at
      FROM kanban_stages WHERE kanban_pipeline_id = #{quote(pipeline_id)} ORDER BY position, id
    SQL
  end

  def insert_step(board_id, stage, index)
    select_value(<<~SQL.squish)
      INSERT INTO funnel_steps
        (funnel_board_id, name, description, color, rank, stage_type, probability,
         created_at, updated_at)
      VALUES
        (#{quote(board_id)}, #{quote(stage['name'])}, NULL, #{quote(stage['color_hex'])},
         #{(index + 1) * 1000}, #{stage_type_for(stage)}, #{probability_for(stage)},
         #{quote(stage['created_at'])}, #{quote(stage['updated_at'])})
      RETURNING id
    SQL
  end

  def stage_type_for(stage)
    return 1 if stage['is_won_stage']
    return 2 if stage['is_lost_stage']

    0
  end

  # A etapa de ganho fecha por definicao, entao 100%. O resto fica em zero para o operador
  # preencher, que e o que alimenta o funil ponderado do relatorio.
  def probability_for(stage)
    stage['is_won_stage'] ? 100 : 0
  end

  def insert_tasks(pipeline_id, board_id, step_ids)
    legacy_tasks(pipeline_id).group_by { |task| task['kanban_stage_id'] }.each do |stage_id, tasks|
      step_id = step_ids[stage_id]
      next if step_id.nil?

      tasks.each_with_index { |task, index| insert_task(board_id, step_id, task, index) }
    end
  end

  def legacy_tasks(pipeline_id)
    select_all(<<~SQL.squish).to_a
      SELECT id, account_id, kanban_stage_id, conversation_id, contact_id, assigned_agent_id, title,
             summary, priority, due_date, stage_entered_at, metadata, position, value_cents,
             loss_reason, created_at, updated_at
      FROM kanban_tasks WHERE kanban_pipeline_id = #{quote(pipeline_id)}
      ORDER BY kanban_stage_id, position, id
    SQL
  end

  def insert_task(board_id, step_id, task, index)
    task_id = select_value(<<~SQL.squish)
      INSERT INTO funnel_tasks
        (account_id, funnel_board_id, funnel_step_id, title, description, priority, rank, start_at,
         due_at, archived_at, custom_attributes, lock_version, value, step_changed_at,
         created_at, updated_at)
      VALUES
        (#{quote(task['account_id'])}, #{quote(board_id)}, #{quote(step_id)}, #{quote(task['title'])},
         #{quote(task['summary'])}, #{quote(task['priority'])}, #{(index + 1) * 1000}, NULL,
         #{quote(task['due_date'])}, NULL, #{quote(attributes_for(task))}, 0, #{value_for(task)},
         #{quote(task['stage_entered_at'])}, #{quote(task['created_at'])}, #{quote(task['updated_at'])})
      RETURNING id
    SQL
    link_associations(board_id, task_id, task)
  end

  # Zero no antigo era o default da coluna, ou seja "ninguem preencheu". Aqui zero afirmaria que a
  # oportunidade nao vale nada, entao vira null — a mesma distincao que o card e o agente leem.
  def value_for(task)
    cents = task['value_cents'].to_i
    cents.zero? ? 'NULL' : quote(BigDecimal(cents) / 100)
  end

  # loss_reason nao tem coluna propria aqui; entra no bag de atributos do card, que e onde o
  # operador e o agente conseguem ler e escrever.
  def attributes_for(task)
    bag = parse_metadata(task['metadata'])
    bag['loss_reason'] = task['loss_reason'] if task['loss_reason'].present?
    bag.to_json
  end

  def parse_metadata(raw)
    return raw if raw.is_a?(Hash)
    return {} if raw.blank?

    parsed = JSON.parse(raw)
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError
    {}
  end

  def link_associations(board_id, task_id, task)
    link(task_id, 'funnel_task_conversations', 'conversation_id', 'conversations', task['conversation_id'],
         columns: 'funnel_board_id, is_primary, active', values: "#{quote(board_id)}, TRUE, TRUE")
    link(task_id, 'funnel_task_contacts', 'contact_id', 'contacts', task['contact_id'])
    link(task_id, 'funnel_task_assignees', 'user_id', 'users', task['assigned_agent_id'])
  end

  # INSERT ... SELECT em vez de VALUES: a conversa, o contato ou o agente podem ter sido apagados
  # desde que o card foi criado, e ai a linha simplesmente nao nasce, em vez de a migracao inteira
  # morrer numa foreign key.
  def link(task_id, table, column, source, value, columns: nil, values: nil)
    return if value.blank?

    all_columns = ['funnel_task_id', column, columns].compact.join(', ')
    all_values = [quote(task_id), 'id', values].compact.join(', ')
    execute(<<~SQL.squish)
      INSERT INTO #{table} (#{all_columns}, created_at, updated_at)
      SELECT #{all_values}, NOW(), NOW() FROM #{source} WHERE id = #{quote(value)}
    SQL
  end
end
