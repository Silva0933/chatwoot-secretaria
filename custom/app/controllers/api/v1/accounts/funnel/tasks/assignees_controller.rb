# PUT substitui o conjunto inteiro; nao ha add/remove porque o multiselect do card manda a
# lista final. O diff e o evento de auditoria ficam no servico.
class Api::V1::Accounts::Funnel::Tasks::AssigneesController < Api::V1::Accounts::Funnel::Tasks::BaseController
  def update
    @task = Funnel::Tasks::ReplaceAssociationService.new(
      task: @task,
      kind: :assignees,
      ids: params[:user_ids],
      actor: Current.user
    ).perform

    render 'api/v1/accounts/funnel/tasks/show'
  end
end
