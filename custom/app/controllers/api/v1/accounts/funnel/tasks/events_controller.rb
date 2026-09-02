# Trilha de auditoria do card. Somente leitura: os eventos sao gravados pelos servicos que
# mudam o card, nunca pelo cliente.
class Api::V1::Accounts::Funnel::Tasks::EventsController < Api::V1::Accounts::Funnel::Tasks::BaseController
  RECENT_LIMIT = 50

  def index
    @events = @task.events.includes(:actor).limit(RECENT_LIMIT)
  end

  private

  # Ler o historico exige apenas enxergar o card, nao poder edita-lo.
  def check_authorization
    authorize(@task, :show?)
  end
end
