# Injetado em Conversation por Conversation.include_mod_with('Concerns::Conversation').
# Ao contrario da implementacao de referencia, que gravou kanban_task_id direto em
# conversations, o vinculo vive na tabela de juncao: uma conversa pode estar em cards de
# quadros diferentes, e a tabela mais quente do Chatwoot nao muda de forma.
module Custom::Concerns::Conversation
  extend ActiveSupport::Concern

  included do
    has_many :funnel_task_conversations, class_name: 'Funnel::TaskConversation', dependent: :destroy
    has_many :funnel_tasks, through: :funnel_task_conversations, source: :task
  end

  # Card ativo desta conversa no quadro informado, se houver.
  def active_funnel_task_for(board_id)
    funnel_task_conversations.active.find_by(funnel_board_id: board_id)&.task
  end
end
