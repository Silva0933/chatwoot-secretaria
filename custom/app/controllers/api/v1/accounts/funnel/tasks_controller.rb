class Api::V1::Accounts::Funnel::TasksController < Api::V1::Accounts::Funnel::BaseController
  before_action :fetch_board
  before_action :fetch_task, except: [:index, :create]
  before_action :check_authorization

  def index
    @tasks = policy_scope(Funnel::Task.where(funnel_board_id: @board.id).active)
             .includes(:assignees, :labels, :contacts, task_conversations: :conversation)
             .order(:rank)
  end

  def show; end

  def create
    @task = Funnel::Task.new(permitted_params)
    @task.board = @board
    @task.step ||= @board.entry_step
    @task.created_by = Current.user
    @task.save!
    render :show
  end

  def update
    @task.update!(permitted_params)
    render :show
  rescue ActiveRecord::StaleObjectError
    render json: { error: 'This task was changed by someone else. Reload and try again.' }, status: :conflict
  end

  def move
    @task = Funnel::Tasks::MoveService.new(
      task: @task,
      step: @board.steps.find(params[:step_id]),
      after_id: params[:after_id],
      before_id: params[:before_id],
      actor: Current.user
    ).perform
    render :show
  rescue Funnel::Tasks::MoveService::InvalidStep => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    @task.update!(archived_at: Time.current)
    head :ok
  end

  private

  def fetch_board
    @board = Current.account.funnel_boards.find(params[:board_id])
  end

  def fetch_task
    @task = Funnel::Task.where(funnel_board_id: @board.id).find(params[:id])
  end

  # Em index e create ainda nao ha card, mas Funnel::TaskPolicy precisa do quadro para achar a
  # participacao do usuario. Um card em memoria com o board preenchido resolve; passar a classe
  # faria a policy chamar funnel_board_id em Class e estourar NoMethodError.
  def check_authorization
    authorize(@task || Funnel::Task.new(funnel_board_id: @board.id))
  end

  def permitted_params
    params.require(:task).permit(
      :title, :description, :priority, :funnel_step_id, :start_at, :due_at, :lock_version,
      custom_attributes: {}
    )
  end
end
