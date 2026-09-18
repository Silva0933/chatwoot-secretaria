# O card endereçado pela conversa, e nao pelo id do card.
#
# Todo o resto deste namespace e endereçado por id de card, que um agente de IA respondendo uma
# mensagem nao tem e nao deveria ter de descobrir. Aqui a conversa e a chave e a etapa vai pelo
# nome, entao quem chama trabalha nos mesmos termos de quem esta conversando.
#
# O id da conversa e o display_id, como em todo o resto da API do Chatwoot — nao a chave primaria.
# O projeto fazer.ai agents guarda justamente o display_id (`chatwoot_conversation_id`) e a doc
# dele registra a recusa deliberada de aceitar os dois: cair para a chave primaria transformaria
# um 404 seguro em "a conversa errada", que aqui significaria mover o card de outro paciente.
class Api::V1::Accounts::Kanban::ConversationCardsController < Api::V1::Accounts::Kanban::BaseController
  before_action :fetch_task
  before_action :check_authorization

  def show; end

  def move
    step = matching_step
    return render_unknown_step if step.blank?

    @task = Funnel::Tasks::MoveService.new(task: @task, step: step, actor: Current.user, source: 'agent').perform
    render :show
  rescue Funnel::Tasks::MoveService::InvalidStep => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def conversation
    @conversation ||= Current.account.conversations.find_by!(display_id: params[:conversation_id])
  end

  # Sem card, 404 — e nao um corpo vazio com 200. O agente distingue "esta conversa ainda nao
  # entrou no funil" de "entrou e esta em tal etapa", e um 200 vazio faria as duas parecerem iguais.
  def fetch_task
    @task = Funnel::Task.for_conversation(conversation.id)
    raise ActiveRecord::RecordNotFound, 'no funnel card for this conversation' if @task.blank?
  end

  def check_authorization
    authorize(@task, action_name == 'show' ? :show? : :update?)
  end

  # Insensivel a acento e a caixa: quem escreve "agendado" quer a mesma etapa que "Agendado", e um
  # modelo que perdeu o acento nao deve falhar a mudanca por causa disso.
  def matching_step
    wanted = normalize(params[:stage])
    return if wanted.blank?

    @task.board.steps.find { |step| normalize(step.name) == wanted }
  end

  def normalize(value)
    I18n.transliterate(value.to_s).downcase.strip
  end

  # Os nomes validos viajam junto com o erro para quem errou o palpite se corrigir na chamada
  # seguinte em vez de adivinhar de novo. O corpo chega ao modelo mesmo em resposta 4xx.
  def render_unknown_step
    render json: {
      error: "unknown stage #{params[:stage].to_s.strip.inspect}",
      valid_stages: @task.board.steps.ordered.map(&:name)
    }, status: :unprocessable_entity
  end
end
