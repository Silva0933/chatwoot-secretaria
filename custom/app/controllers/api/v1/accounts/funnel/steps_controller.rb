# Etapas do quadro. Autoriza por manage_settings?, nao por update?: mexer nas colunas muda o
# funil para todo mundo, enquanto arrastar um card e trabalho do dia a dia de qualquer membro.
class Api::V1::Accounts::Funnel::StepsController < Api::V1::Accounts::Funnel::BaseController
  before_action :fetch_board
  before_action :fetch_step, only: [:update, :destroy]
  before_action :check_authorization

  def create
    @board.steps.create!(permitted_params)
    render_board
  end

  def update
    @step.update!(permitted_params)
    render_board
  end

  # Excluir etapa com cards exige dizer para onde eles vao: a associacao e restrict_with_error,
  # e apagar em silencio levaria junto o historico de atendimento de cada card.
  def destroy
    return render_error('A board needs at least one stage', :unprocessable_entity) if @board.steps.count <= 1

    ActiveRecord::Base.transaction do
      move_tasks_out if @step.tasks.exists?
      @step.destroy!
    end

    render_board
  rescue ActiveRecord::RecordInvalid => e
    render_error(e.message, :unprocessable_entity)
  end

  # Reordenar por arrasto: o cliente manda a ordem final dos ids, e cada etapa recebe um rank
  # espacado. Reescrever a coluna inteira aqui e barato — sao poucas etapas, ao contrario dos
  # cards, onde o rank fracionario existe justamente para evitar isso.
  def reorder
    ids = Array(params[:step_ids]).map(&:to_i)
    steps = @board.steps.where(id: ids).index_by(&:id)
    return render_error('unknown stage in the given order', :unprocessable_entity) if steps.size != ids.size

    ActiveRecord::Base.transaction do
      ids.each_with_index { |id, index| steps[id].update!(rank: Funnel::Ranking::STEP * (index + 1)) }
    end

    render_board
  end

  private

  def fetch_board
    @board = Current.account.funnel_boards.find(params[:board_id])
  end

  def fetch_step
    @step = @board.steps.find(params[:id])
  end

  def check_authorization
    authorize(@board, :manage_settings?)
  end

  def move_tasks_out
    target = @board.steps.where.not(id: @step.id).find_by(id: params[:target_step_id]) ||
             @board.steps.where.not(id: @step.id).ordered.first

    @step.tasks.find_each do |task|
      Funnel::Tasks::MoveService.new(task: task, step: target, actor: Current.user).perform
    end
  end

  def render_board
    @board.reload
    render 'api/v1/accounts/funnel/boards/show'
  end

  def render_error(message, status)
    render json: { error: message }, status: status
  end

  def permitted_params
    params.require(:step).permit(:name, :description, :color, :stage_type)
  end
end
