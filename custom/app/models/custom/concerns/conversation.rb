# Injetado em Conversation por Conversation.include_mod_with('Concerns::Conversation').
# Ao contrario da implementacao de referencia, que gravou kanban_task_id direto em
# conversations, o vinculo vive na tabela de juncao: uma conversa pode estar em cards de
# quadros diferentes, e a tabela mais quente do Chatwoot nao muda de forma.
module Custom::Concerns::Conversation
  extend ActiveSupport::Concern

  WHATSAPP_GROUP_JID_SUFFIX = '@g.us'.freeze

  included do
    has_many :funnel_task_conversations, class_name: 'Funnel::TaskConversation', dependent: :destroy
    has_many :funnel_tasks, through: :funnel_task_conversations, source: :task
  end

  # Card ativo desta conversa no quadro informado, se houver.
  def active_funnel_task_for(board_id)
    funnel_task_conversations.active.find_by(funnel_board_id: board_id)&.task
  end

  # Conversa de grupo. O WhatsApp identifica grupo pelo sufixo do JID (@g.us), e o Baileys grava
  # esse JID inteiro no identifier do contato; contato de pessoa traz @lid ou @s.whatsapp.net e um
  # telefone. Conferido na instancia: os dois grupos do quadro tinham identifier terminado em
  # @g.us e phone_number nulo, e a conversa de pessoa tinha 161447954874419@lid com telefone.
  #
  # Ler o IDENTIFIER e nao a ausencia de telefone: contato de outro canal (webchat, email) tambem
  # nao tem telefone, e tratar todos eles como grupo tiraria do funil justamente os leads que
  # chegam por fora do WhatsApp. O sufixo e especifico e so um grupo o tem.
  #
  # O contato e sempre carregavel (belongs_to obrigatorio, contact_id null: false), e o identifier
  # e que pode vir nulo — canal sem JID nenhum passa pelo to_s e responde que nao e grupo.
  def group_conversation?
    contact.identifier.to_s.end_with?(WHATSAPP_GROUP_JID_SUFFIX)
  end
end
