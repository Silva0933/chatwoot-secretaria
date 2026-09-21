class Funnel::TaskConversation < ApplicationRecord
  belongs_to :task, class_name: 'Funnel::Task', foreign_key: :funnel_task_id, inverse_of: :task_conversations
  belongs_to :conversation

  # funnel_board_id e active espelham o card. Copiados em before_save e nao em
  # before_validation porque save(validate: false) pula as validacoes mas nao os callbacks de
  # save: no before_validation as colunas chegariam nulas ao banco justamente no caminho que
  # depende do unique index parcial para barrar duplicata.
  before_save :copy_columns_from_task

  # Vincular ou desvincular um card muda o payload de evento da conversa, e quem consome esse
  # payload so o recebe quando a conversa dispara evento. Sem este re-disparo, um card criado por
  # um atendente so alcanca o agente na proxima mensagem do cliente — e um follow-up proativo,
  # que nao e disparado por mensagem nenhuma, nunca o veria.
  #
  # Mover o card entre etapas ou editar seus campos NAO re-dispara, de proposito: e o que a
  # fazer.ai Pro faz, e o cliente do agente esta escrito contra esse comportamento. Para essas
  # mudancas ele le o card ao vivo pela API, no preparo do turno.
  after_commit :dispatch_conversation_updated, on: [:create, :destroy]
  after_commit :archive_orphaned_task, on: :destroy

  validates :conversation_id, uniqueness: { scope: :funnel_task_id }
  validate :conversation_belongs_to_task_account
  validate :single_active_task_per_board, on: :create

  scope :active, -> { where(active: true) }

  # Rebaixa o vinculo principal do card, se houver. Fica aqui porque tanto o vinculo novo
  # quanto a promocao de um existente precisam disso antes de marcar o seu.
  #
  # update_all e proposital: e uma troca de flag em massa, nenhuma validacao do modelo depende
  # de is_primary, e o caminho por registro custaria uma query por linha.
  def self.demote_primary_of(task)
    where(funnel_task_id: task.id, is_primary: true)
      .update_all(is_primary: false, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  private

  def copy_columns_from_task
    self.funnel_board_id = task.funnel_board_id
    self.active = task.archived_at.nil?
  end

  # Conversa destruida leva os vinculos junto (dependent: :destroy). Anunciar atualizacao de uma
  # conversa que acabou de sumir manda o consumidor buscar o que nao existe mais.
  def dispatch_conversation_updated
    return if conversation.blank? || conversation.destroyed?

    conversation.dispatch_conversation_updated_event
  end

  # Conversa apagada no Chatwoot levava o vinculo junto (dependent: :destroy) e deixava o CARD
  # para tras: um card sem conversa e sem contato, que o quadro continuava desenhando e ninguem
  # mais conseguia abrir. Nenhum listener cobria isso — CONVERSATION_DELETED viaja com
  # `conversation_data`, um hash de contagem, e nao com a conversa, entao o FunnelAutomationListener
  # nao tem o que extrair. Aqui o vinculo morrendo E o aviso, e chega sempre.
  #
  # Arquivar e o nosso excluir e e reversivel; dispatch_updated traduz archived_at em
  # 'funnel.task.deleted', entao o quadro aberto ve o card sumir sozinho.
  #
  # So quando a CONVERSA foi destruida. Desvincular um card a mao passa por este mesmo destroy, e
  # ali o gesto e "este card nao e desta conversa" e nao "este card acabou" — apagar o card seria
  # perder trabalho de quem so quis corrigir um vinculo. Apagar um quadro tambem chega aqui, com a
  # conversa viva, e nao deve arquivar nada alem do que a cascata ja leva.
  def archive_orphaned_task
    return unless conversation.nil? || conversation.destroyed?

    # Card com outra conversa ainda vinculada continua sendo um atendimento em curso. Consultado
    # no banco e nao pela associacao: `task.task_conversations` ja esta cacheada com o vinculo que
    # acabou de sumir, e leria uma lista que nao existe mais.
    return if self.class.exists?(funnel_task_id: funnel_task_id)

    task = Funnel::Task.find_by(id: funnel_task_id)
    return if task.nil? || task.archived?

    task.update!(archived_at: Time.current)
  end

  def conversation_belongs_to_task_account
    return if conversation.blank? || task.blank?
    return if conversation.account_id == task.account_id

    errors.add(:conversation, 'must belong to the same account as the task')
  end

  # O unique index parcial e a garantia real contra corrida; esta validacao existe para o erro
  # chegar ao usuario como mensagem e nao como RecordNotUnique. Le do card e nao das colunas
  # copiadas, que so sao preenchidas no before_save.
  def single_active_task_per_board
    return if task.blank? || conversation_id.blank?
    return unless task.archived_at.nil?
    return if self.class.active.where(funnel_board_id: task.funnel_board_id, conversation_id: conversation_id).none?

    errors.add(:conversation, 'is already linked to an active task on this board')
  end
end
