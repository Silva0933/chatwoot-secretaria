# Guarda unica do modulo: o toggle da conta e checado aqui e nao repetido nos filhos.
class Api::V1::Accounts::Funnel::BaseController < Api::V1::Accounts::BaseController
  before_action :ensure_feature_enabled

  private

  def ensure_feature_enabled
    return if Current.account.funnel_kanban_enabled?

    render json: { error: 'Funnel Kanban is not enabled for this account' }, status: :forbidden
  end
end
