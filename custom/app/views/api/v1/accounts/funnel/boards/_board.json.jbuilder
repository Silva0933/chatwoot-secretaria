json.id board.id
json.name board.name
json.description board.description
json.currency board.currency
json.archived_at board.archived_at
json.created_at board.created_at
json.steps board.steps.map do |step|
  json.id step.id
  json.name step.name
  json.description step.description
  json.color step.color
  json.rank step.rank.to_s
  json.stage_type step.stage_type
  json.probability step.probability
end

# O papel do usuario no quadro nao esta em lugar nenhum que o frontend possa deduzir: a
# permissao vem de funnel_board_members e nao do papel na conta. Sem isto a interface so
# descobriria que uma acao e proibida pela recusa da API (401, ver RequestExceptionHandler),
# depois de o usuario tentar.
current_membership = board.members.detect { |member| member.user_id == Current.user&.id }
current_user_is_admin = Current.account_user&.administrator?

json.members board.members.map do |member|
  json.user_id member.user_id
  json.name member.user.name
  json.role member.role
  json.visibility_scope member.visibility_scope
end
json.inbox_ids board.board_inboxes.map(&:inbox_id)

json.current_user_role current_membership&.role
json.permissions do
  json.manage_board current_user_is_admin.present?
  json.manage_settings current_user_is_admin.present? || current_membership&.role_manager? || false
  json.create_task current_user_is_admin.present? || current_membership&.role_manager? || current_membership&.role_member? || false
end
