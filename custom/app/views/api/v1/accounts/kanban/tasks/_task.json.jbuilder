# Formato do card no contrato da fazer.ai Pro, que o cliente do fazer.ai agents parseia.
# Nomes diferem do nosso Funnel de proposito: board_step_id e nao funnel_step_id, start_date e
# nao start_at, labels como texto e nao como id.
json.id task.id
json.board_id task.funnel_board_id
json.board_step_id task.funnel_step_id
json.title task.title
json.description task.description
json.priority task.priority
# O agente mostra "status" ao modelo como o estado do card. O que temos de mais proximo e o tipo
# da etapa onde ele esta: open, won ou lost.
json.status task.step.stage_type
# Valor monetario ainda nao existe no modulo (relatorio 4.7). Vai null em vez de zero: zero
# afirmaria que a oportunidade vale nada, null diz que nao sabemos.
json.value nil
json.start_date task.start_at
json.due_date task.due_at
json.custom_attributes task.custom_attributes
json.labels task.labels.map(&:title)
json.created_at task.created_at
json.updated_at task.updated_at

json.board do
  json.id task.board.id
  json.name task.board.name
end
