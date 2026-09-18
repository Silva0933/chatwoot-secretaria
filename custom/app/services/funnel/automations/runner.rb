# Motor de automacoes do quadro (relatorio 4.10).
#
# O relatorio pede explicitamente para NAO espalhar callbacks pelos models: um motor unico, com
# registro de cada execucao. O motivo e pratico — automacao sem registro vira comportamento
# magico, o card se move sozinho e ninguem consegue dizer por que.
#
# As seis regras confirmadas sao booleanos por quadro. Nao ha construtor visual de regras aqui;
# quando existir, ele entra como mais uma fonte de RULES sem mexer no resto.
class Funnel::Automations::Runner
  RULES = %w[
    create_task_on_conversation
    auto_assign_task
    win_task_on_conversation_resolved
    resolve_conversation_on_final_step
    sync_assignees
    sync_labels_and_priority
  ].freeze

  class << self
    # Reentrancia e o risco central: sincronizar responsavel nos dois sentidos faz a mudanca no
    # card disparar a mudanca na conversa, que dispara a do card, para sempre. Uma automacao
    # nunca dispara outra — a primeira execucao da cadeia e a unica.
    def running?
      Thread.current[:funnel_automation_running].present?
    end

    def with_guard
      return if running?

      Thread.current[:funnel_automation_running] = true
      begin
        yield
      ensure
        Thread.current[:funnel_automation_running] = nil
      end
    end
  end

  def initialize(board:, event_name:, conversation: nil, task: nil)
    @board = board
    @event_name = event_name
    @conversation = conversation
    @task = task
  end

  def call(rule)
    return unless RULES.include?(rule)
    return unless enabled?(rule)

    self.class.with_guard do
      result = public_send(:"apply_#{rule}")
      record(rule, status: 'ok', data: { result: result })
    end
  rescue StandardError => e
    # Uma automacao que falha nao pode derrubar a acao que a disparou: o atendente resolveu a
    # conversa, e isso aconteceu, mesmo que mover o card tenha dado errado. O erro fica no
    # registro para alguem investigar.
    record(rule, status: 'error', error: "#{e.class}: #{e.message}")
    Rails.logger.error("[funnel automation] #{rule} failed: #{e.class}: #{e.message}")
    nil
  end

  def apply_create_task_on_conversation
    return 'already linked' if existing_task.present?

    task = Funnel::Task.new(
      board: @board,
      step: @board.entry_step,
      title: @conversation.contact&.name.presence || "##{@conversation.display_id}"
    )
    task.save!
    task.task_contacts.create!(contact: @conversation.contact) if @conversation.contact.present?
    Funnel::Tasks::LinkConversationService.new(
      task: task, conversation: @conversation, primary: true, source: 'automation'
    ).perform

    @task = task
    "created task #{task.id}"
  end

  def apply_auto_assign_task
    task = @task || existing_task
    return 'no task' if task.blank?

    assignee = @conversation&.assignee
    return 'conversation has no assignee' if assignee.blank?

    replace_association(task, :assignees, [assignee.id])
    "assigned #{assignee.id}"
  end

  def apply_win_task_on_conversation_resolved
    task = existing_task
    return 'no task' if task.blank?

    target = @board.steps.stage_won.ordered.first
    return 'board has no won stage' if target.blank?

    move(task, target)
  end

  # O card chegou a uma etapa de fechamento, entao o atendimento acabou.
  def apply_resolve_conversation_on_final_step
    return 'task still open' unless closing_step?

    resolvable = @task.task_conversations.map(&:conversation).select(&:open?)
    return 'nothing to resolve' if resolvable.empty?

    resolvable.each(&:toggle_status)
    "resolved #{resolvable.map(&:display_id).join(',')}"
  end

  def apply_sync_assignees
    task = @task || existing_task
    return 'no task' if task.blank?

    if @event_name.to_s.start_with?('funnel.')
      sync_assignee_to_conversations(task)
    else
      apply_auto_assign_task
    end
  end

  def apply_sync_labels_and_priority
    task = @task || existing_task
    return 'no task' if task.blank? || @conversation.blank?

    if @event_name.to_s.start_with?('funnel.')
      @conversation.update!(priority: task.priority) if task.priority != @conversation.priority
      'priority pushed to conversation'
    else
      task.update!(priority: @conversation.priority) if task.priority != @conversation.priority
      'priority pulled from conversation'
    end
  end

  private

  def closing_step?
    @task.present? && !@task.step.stage_open?
  end

  def enabled?(rule)
    ActiveModel::Type::Boolean.new.cast(@board.automation_settings[rule]).present?
  end

  def existing_task
    return @task if @task.present?
    return nil if @conversation.blank?

    @existing_task ||= Funnel::Task.active
                                   .where(funnel_board_id: @board.id)
                                   .where(id: Funnel::TaskConversation.active
                                                                      .where(conversation_id: @conversation.id)
                                                                      .select(:funnel_task_id))
                                   .first
  end

  def move(task, step)
    return "already on #{step.name}" if task.funnel_step_id == step.id

    Funnel::Tasks::MoveService.new(task: task, step: step, source: 'automation').perform
    "moved to #{step.name}"
  end

  def replace_association(task, kind, ids)
    Funnel::Tasks::ReplaceAssociationService.new(task: task, kind: kind, ids: ids, source: 'automation').perform
  end

  def sync_assignee_to_conversations(task)
    assignee = task.assignees.first
    return 'task has no assignee' if assignee.blank?

    task.task_conversations.each do |link|
      link.conversation.update!(assignee: assignee) if link.conversation.assignee_id != assignee.id
    end
    "pushed assignee #{assignee.id}"
  end

  def record(rule, status:, data: {}, error: nil)
    Funnel::AutomationRun.create!(
      account_id: @board.account_id,
      funnel_board_id: @board.id,
      funnel_task_id: (@task || @existing_task)&.id,
      conversation_id: @conversation&.id,
      rule: rule,
      event_name: @event_name,
      status: status,
      data: data.compact,
      error: error
    )
  end
end
