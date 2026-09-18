class Api::V1::Accounts::Kanban::TasksController < Api::V1::Accounts::Kanban::BaseController
  class LabelRejected < StandardError; end

  before_action :fetch_task, except: [:index, :create]
  before_action :check_authorization

  def index
    scope = Funnel::Task.active.where(account_id: Current.account.id)
    scope = scope.where(funnel_board_id: params[:board_id]) if params[:board_id].present?

    @tasks = policy_scope(scope).includes(:board, :step, :labels).order(:rank)
  end

  def show; end

  def create
    board = fetch_board!(task_params[:board_id] || params[:board_id])
    @task = Funnel::Task.new(scalar_params)
    @task.board = board
    @task.step = board.steps.find_by(id: task_params[:board_step_id]) || board.entry_step
    @task.created_by = Current.user
    @task.save!

    apply_labels
    render :show
  rescue LabelRejected => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    @task.update!(scalar_params)
    apply_labels
    @task.reload
    render :show
  rescue LabelRejected => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # O contrato da Pro passa a posicao como insert_before_task_id; o nosso MoveService fala em
  # vizinhos, e aquele id e exatamente o vizinho de baixo.
  def move
    @task = Funnel::Tasks::MoveService.new(
      task: @task,
      step: @task.board.steps.find(params[:board_step_id]),
      before_id: params[:insert_before_task_id],
      actor: Current.user,
      source: 'api'
    ).perform
    render :show
  rescue Funnel::Tasks::MoveService::InvalidStep => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def fetch_task
    @task = fetch_task!(params[:id])
  end

  def check_authorization
    return authorize(Funnel::Task) if action_name == 'index'
    return authorize(Funnel::Task.new(funnel_board_id: board_id_for_create), :create?) if action_name == 'create'

    authorize(@task, action_name == 'show' ? :show? : :update?)
  end

  def board_id_for_create
    task_params[:board_id] || params[:board_id]
  end

  def task_params
    @task_params ||= params[:task].presence || ActionController::Parameters.new
  end

  # start_date/due_date do contrato da Pro sao os nossos start_at/due_at. Os demais campos tem o
  # mesmo nome nos dois lados.
  def scalar_params
    permitted = task_params.permit(:title, :description, :priority, :start_date, :due_date, custom_attributes: {})
    attributes = permitted.to_h.symbolize_keys

    attributes[:start_at] = attributes.delete(:start_date) if attributes.key?(:start_date)
    attributes[:due_at] = attributes.delete(:due_date) if attributes.key?(:due_date)
    attributes
  end

  # No contrato da Pro as etiquetas viajam como texto, porque la elas sao acts_as_taggable. Aqui
  # sao registros de Label da conta, entao o texto precisa virar id — criando o que ainda nao
  # existe, que e o comportamento que o agente espera ao marcar uma etiqueta nova.
  def apply_labels
    titles = task_params[:labels]
    return if titles.nil?

    ids = Array(titles).map(&:to_s).map(&:strip).reject(&:empty?).uniq.map do |title|
      # O agente manda texto livre, e o Chatwoot recusa alguns: o formato de Label exige ao
      # menos dois caracteres de letra ou numero. Sem nomear a etiqueta rejeitada, o agente
      # recebe "Title is invalid" e nao tem como saber qual das que mandou quebrou.

      Current.account.labels.find_or_create_by!(title: title).id
    rescue ActiveRecord::RecordInvalid
      raise LabelRejected, "label #{title.inspect} is not a valid Chatwoot label"
    end

    Funnel::Tasks::ReplaceAssociationService.new(
      task: @task, kind: :labels, ids: ids, actor: Current.user, source: 'api'
    ).perform
  end
end
