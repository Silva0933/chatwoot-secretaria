# Relatorio de um quadro (relatorio 4.14).
#
# Duas fontes, e a diferenca entre elas importa: o estado ATUAL dos cards responde "quanto esta
# aberto em cada etapa agora", e a trilha em funnel_task_events responde "quantos passaram de A
# para B", que nenhuma foto do presente consegue dizer. Ganho e perda saem do estado atual com
# step_changed_at dentro do periodo, ou seja "entrou numa etapa de fechamento no periodo" — um
# card que ganhou e depois voltou para aberto deixa de contar, que e o comportamento certo.
class Funnel::Reports::BoardReport
  DEFAULT_PERIOD = 30.days
  # Card parado e o que nao anda ha uma semana. Nao e configuravel ainda: sem alguem pedindo um
  # numero diferente, uma opcao a mais so seria uma decisao a mais para quem le.
  STALLED_AFTER = 7.days
  STALLED_LIST_LIMIT = 20

  def initialize(board:, scope:, since: nil, until_time: nil)
    @board = board
    # O escopo ja vem filtrado pela policy: um membro limitado aos proprios cards le um
    # relatorio dos proprios cards, e nao os numeros do quadro inteiro.
    @scope = scope.where(funnel_board_id: board.id)
    @since = since || DEFAULT_PERIOD.ago
    @until = until_time || Time.current
  end

  def perform
    {
      range: { since: @since, until: @until, currency: @board.currency },
      totals: totals,
      steps: steps,
      transitions: transitions,
      closures: closures,
      agents: agents,
      stalled: stalled
    }
  end

  private

  def active_scope
    @active_scope ||= @scope.active
  end

  def step_types
    @step_types ||= @board.steps.ordered.index_by(&:id)
  end

  def closed_in_period(stage_type)
    active_scope.where(funnel_step_id: step_types.values.select { |s| s.stage_type == stage_type }.map(&:id))
                .where(step_changed_at: @since..@until)
  end

  def totals
    won = closed_in_period('won').count
    lost = closed_in_period('lost').count
    open_scope = active_scope.where(funnel_step_id: open_step_ids)

    {
      created: @scope.where(created_at: @since..@until).count,
      won: won,
      lost: lost,
      # Taxa de ganho sobre o que fechou, nao sobre o total: incluir o que ainda esta aberto
      # afundaria o numero de um funil saudavel so por ter muita coisa em andamento.
      win_rate: (won + lost).zero? ? nil : (won.to_f / (won + lost) * 100).round(1),
      open: open_scope.count,
      open_value: open_scope.sum(:value).to_s,
      weighted_value: weighted_value.to_s
    }
  end

  def open_step_ids
    @open_step_ids ||= step_types.values.select { |step| step.stage_type == 'open' }.map(&:id)
  end

  def weighted_value
    active_scope.where(funnel_step_id: open_step_ids)
                .group(:funnel_step_id)
                .sum(:value)
                .sum { |step_id, value| (value || 0) * (step_types[step_id].probability / 100.0) }
                .round(2)
  end

  def steps
    tallies = {
      counts: active_scope.group(:funnel_step_id).count,
      values: active_scope.group(:funnel_step_id).sum(:value),
      ages: median_age_by_step,
      stalled: active_scope.where(step_changed_at: ...STALLED_AFTER.ago).group(:funnel_step_id).count
    }

    step_types.values.map { |step| step_summary(step, tallies) }
  end

  def step_summary(step, tallies)
    {
      id: step.id, name: step.name, color: step.color, stage_type: step.stage_type,
      probability: step.probability,
      count: tallies[:counts][step.id] || 0,
      value: (tallies[:values][step.id] || 0).to_s,
      median_age_seconds: tallies[:ages][step.id],
      stalled_count: tallies[:stalled][step.id] || 0
    }
  end

  # Mediana e nao media: um unico card esquecido ha oito meses puxa a media da etapa inteira e
  # esconde que o resto anda em dois dias.
  def median_age_by_step
    now = Time.current
    active_scope.pluck(:funnel_step_id, :step_changed_at)
                .group_by(&:first)
                .transform_values do |rows|
                  seconds = rows.map { |(_, changed_at)| (now - changed_at).to_i }.sort
                  middle = seconds.size / 2
                  seconds.size.odd? ? seconds[middle] : ((seconds[middle - 1] + seconds[middle]) / 2)
                end
  end

  # Conversao entre etapas, da trilha de auditoria. E a unica fonte que sabe por onde os cards
  # passaram: o estado atual so mostra onde eles pararam.
  def transitions
    pairs = move_events.filter_map { |before, after| transition_pair(before, after) }

    pairs.tally
         .map { |(from, to), count| { from_step_id: from, to_step_id: to, count: count } }
         .sort_by { |row| -row[:count] }
  end

  def move_events
    Funnel::TaskEvent.where(funnel_task_id: @scope.select(:id), event_type: 'task.moved')
                     .where(created_at: @since..@until)
                     .pluck(:data_before, :data_after)
  end

  # Reordenar dentro da mesma etapa tambem grava task.moved; so a troca de etapa e conversao.
  def transition_pair(before, after)
    from = before&.dig('step_id')
    to = after&.dig('step_id')
    return nil if from.blank? || to.blank? || from == to

    [from, to]
  end

  def closures
    won = closed_in_period('won').group('DATE(step_changed_at)').count
    lost = closed_in_period('lost').group('DATE(step_changed_at)').count

    (won.keys + lost.keys).uniq.sort.map do |date|
      { date: date, won: won[date] || 0, lost: lost[date] || 0 }
    end
  end

  def agents
    won_ids = closed_in_period('won').select(:id)
    lost_ids = closed_in_period('lost').select(:id)

    Funnel::TaskAssignee.where(funnel_task_id: @scope.select(:id))
                        .includes(:user)
                        .group_by(&:user_id)
                        .map { |user_id, rows| agent_row(user_id, rows, won_ids, lost_ids) }
                        .sort_by { |row| [-row[:won], row[:name]] }
  end

  def agent_row(user_id, rows, won_ids, lost_ids)
    task_ids = rows.map(&:funnel_task_id)
    won_scope = @scope.where(id: task_ids & won_ids.map(&:id))

    {
      user_id: user_id,
      name: rows.first.user&.name,
      won: won_scope.count,
      lost: (task_ids & lost_ids.map(&:id)).size,
      open: active_scope.where(id: task_ids, funnel_step_id: open_step_ids).count,
      won_value: won_scope.sum(:value).to_s
    }
  end

  def stalled
    active_scope.where(funnel_step_id: open_step_ids)
                .where(step_changed_at: ...STALLED_AFTER.ago)
                .order(:step_changed_at)
                .limit(STALLED_LIST_LIMIT)
                .map do |task|
                  { id: task.id, title: task.title, step_name: step_types[task.funnel_step_id]&.name,
                    days: ((Time.current - task.step_changed_at) / 1.day).floor }
                end
  end
end
