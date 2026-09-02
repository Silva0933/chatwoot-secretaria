# Adaptador para o formato de Kanban da fazer.ai Pro.
#
# Existe por um motivo so: o projeto fazer.ai agents ja tem um cliente Kanban escrito, testado e
# documentado contra aquele contrato. Reproduzir o formato aqui custa esta camada de traducao;
# mudar o agente custaria o cliente, os testes e a documentacao dele.
#
# Nada de regra de negocio mora aqui. Tudo delega para Funnel::*, que continua sendo o modulo de
# verdade; estes controllers so traduzem nome de rota, nome de parametro e forma de resposta.
class Api::V1::Accounts::Kanban::BaseController < Api::V1::Accounts::BaseController
  before_action :ensure_feature_enabled

  private

  def ensure_feature_enabled
    return if Current.account.funnel_kanban_enabled?

    render json: { error: 'Funnel Kanban is not enabled for this account' }, status: :forbidden
  end

  def fetch_board!(id)
    Current.account.funnel_boards.find(id)
  end

  def fetch_task!(id)
    Current.account.funnel_tasks.find(id)
  end
end
