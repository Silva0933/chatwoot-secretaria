json.partial! 'api/v1/accounts/kanban/tasks/task', task: @task
json.stage_name @task.step.name
json.pipeline_name @task.board.name
# As etapas validas vao junto tambem no sucesso, nao so no erro. A ferramenta "ver card" existe
# para o agente decidir para onde mover; sem a lista aqui, a unica forma de descobri-la e errar
# um nome de proposito e ler a lista da resposta de erro.
json.valid_stages @task.board.steps.ordered.map(&:name)
