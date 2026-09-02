# Substitui por inteiro o conjunto de responsaveis, etiquetas ou contatos de um card.
#
# A API recebe a lista final e nao um par adicionar/remover porque o formulario do card e um
# multiselect: ele sabe o estado final, nao o delta. O diff fica aqui.
#
# As tres associacoes tem a mesma forma — tabela de juncao com uma coluna apontando para fora —
# e por isso compartilham o servico. A tabela KINDS existe para nao ter tres classes identicas
# a menos de dois nomes.
class Funnel::Tasks::ReplaceAssociationService
  class UnknownKind < StandardError; end

  KINDS = {
    assignees: { association: :task_assignees, foreign_key: :user_id, event_type: 'task.assignees_replaced' },
    labels: { association: :task_labels, foreign_key: :label_id, event_type: 'task.labels_replaced' },
    contacts: { association: :task_contacts, foreign_key: :contact_id, event_type: 'task.contacts_replaced' }
  }.freeze

  def initialize(task:, kind:, ids:, actor: nil, source: 'web')
    @task = task
    @kind = kind.to_sym
    @ids = Array(ids).map(&:to_i).uniq
    @actor = actor
    @source = source
  end

  def perform
    raise UnknownKind, "unknown association #{@kind}" unless KINDS.key?(@kind)

    ActiveRecord::Base.transaction do
      before = current_ids
      apply(before)
      record_event(before) if before.sort != @ids.sort
    end

    @task.reload
  end

  private

  def config
    KINDS.fetch(@kind)
  end

  def scope
    @task.public_send(config[:association])
  end

  def current_ids
    scope.pluck(config[:foreign_key])
  end

  # Remove e cria so o que mudou, em vez de apagar tudo e recriar. Recriar faria o card perder
  # o created_at de um vinculo que nao foi tocado, e e ele que ordena a lista na tela.
  def apply(before)
    removed = before - @ids
    added = @ids - before

    scope.where(config[:foreign_key] => removed).destroy_all if removed.any?
    added.each { |id| scope.create!(config[:foreign_key] => id) }
  end

  def record_event(before)
    Funnel::TaskEvent.create!(
      task: @task,
      account_id: @task.account_id,
      actor: @actor,
      event_type: config[:event_type],
      source: @source,
      data_before: { ids: before },
      data_after: { ids: @ids }
    )
  end
end
