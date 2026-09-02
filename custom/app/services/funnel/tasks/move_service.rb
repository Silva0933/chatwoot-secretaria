# Move um card para outra etapa e/ou outra posicao dentro da etapa.
#
# A posicao chega como os ids dos vizinhos (+after_id+ e +before_id+) e nao como um indice.
# Indice quebra em concorrencia: dois agentes arrastando ao mesmo tempo calculam o mesmo indice
# a partir de leituras diferentes do quadro. Os vizinhos identificam o intervalo de destino
# mesmo que a lista tenha mudado desde que o navegador a carregou.
class Funnel::Tasks::MoveService
  class InvalidStep < StandardError; end

  def initialize(task:, step:, after_id: nil, before_id: nil, actor: nil, source: 'web')
    @task = task
    @step = step
    @after_id = after_id
    @before_id = before_id
    @actor = actor
    @source = source
  end

  def perform
    raise InvalidStep, 'step must belong to the same board as the task' if @step.funnel_board_id != @task.funnel_board_id

    previous_state = nil

    @task.with_lock do
      # Capturado apos o with_lock: ele recarrega a linha, entao antes daqui o estado ainda e o
      # que o navegador tinha, que pode estar velho.
      previous_state = capture_state
      rebalance_step if rebalance_needed?
      @task.update!(step: @step, rank: target_rank)
    end

    record_event(previous_state)
    @task
  end

  private

  def capture_state
    { step_id: @task.funnel_step_id, rank: @task.rank&.to_s }
  end

  def neighbours
    @neighbours ||= begin
      scope = Funnel::Task.where(funnel_step_id: @step.id).where.not(id: @task.id)
      { after: @after_id && scope.find_by(id: @after_id), before: @before_id && scope.find_by(id: @before_id) }
    end
  end

  def rebalance_needed?
    Funnel::Ranking.rebalance_needed?(neighbours[:after]&.rank, neighbours[:before]&.rank)
  end

  # Redistribui os ranks da etapa de destino quando os vizinhos ficaram proximos demais para
  # caber outro ponto medio. Roda dentro do lock do card que esta sendo movido.
  def rebalance_step
    ordered_ids = Funnel::Task.where(funnel_step_id: @step.id).order(:rank, :id).pluck(:id)
    Funnel::Ranking.rebalance(ordered_ids).each do |id, new_rank|
      Funnel::Task.where(id: id).update_all(rank: new_rank)
    end
    @neighbours = nil
  end

  def target_rank
    Funnel::Ranking.between(neighbours[:after]&.rank, neighbours[:before]&.rank)
  end

  def record_event(previous_state)
    return if previous_state[:step_id] == @task.funnel_step_id && previous_state[:rank] == @task.rank.to_s

    Funnel::TaskEvent.create!(
      task: @task,
      account_id: @task.account_id,
      actor: @actor,
      event_type: 'task.moved',
      source: @source,
      data_before: previous_state,
      data_after: { step_id: @task.funnel_step_id, rank: @task.rank.to_s }
    )
  end
end
