class Funnel::Task < ApplicationRecord
  belongs_to :account
  belongs_to :board, class_name: 'Funnel::Board', foreign_key: :funnel_board_id, inverse_of: :tasks
  belongs_to :step, class_name: 'Funnel::Step', foreign_key: :funnel_step_id, inverse_of: :tasks
  belongs_to :created_by, class_name: 'User', optional: true

  has_many :task_conversations, class_name: 'Funnel::TaskConversation', foreign_key: :funnel_task_id, dependent: :destroy,
                                inverse_of: :task
  has_many :conversations, through: :task_conversations
  has_many :task_contacts, class_name: 'Funnel::TaskContact', foreign_key: :funnel_task_id, dependent: :destroy, inverse_of: :task
  has_many :contacts, through: :task_contacts
  has_many :task_assignees, class_name: 'Funnel::TaskAssignee', foreign_key: :funnel_task_id, dependent: :destroy, inverse_of: :task
  has_many :assignees, through: :task_assignees, source: :user
  has_many :task_labels, class_name: 'Funnel::TaskLabel', foreign_key: :funnel_task_id, dependent: :destroy, inverse_of: :task
  has_many :labels, through: :task_labels
  has_many :events, -> { order(created_at: :desc) }, class_name: 'Funnel::TaskEvent', foreign_key: :funnel_task_id,
                                                     dependent: :delete_all, inverse_of: :task

  # Mesma escala de Conversation#priority, nil incluso, para que espelhar prioridade entre card
  # e conversa na Fase 3 seja atribuicao direta e nao tabela de conversao.
  enum priority: { low: 0, medium: 1, high: 2, urgent: 3 }

  validates :title, presence: true, length: { maximum: 255 }
  validates :rank, presence: true
  validates :value, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :step_belongs_to_board
  validate :board_belongs_to_account

  before_validation :assign_account_from_board, on: :create
  before_validation :assign_default_rank, on: :create
  before_validation :stamp_step_changed_at, on: :create
  after_update_commit :sync_conversation_link_columns, if: :conversation_link_columns_changed?

  # O evento sai de callback e nao de cada controller de proposito: o quadro tambem e escrito
  # pelo adaptador /kanban e pelo agente, e um disparo por chamador deixaria esses caminhos
  # mudos. Aqui e o ponto por onde toda escrita passa.
  after_commit :dispatch_created, on: :create
  after_commit :dispatch_updated, on: :update

  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }
  scope :in_step, ->(step_id) { where(funnel_step_id: step_id).order(:rank) }
  scope :overdue, -> { active.where(due_at: ...Time.current) }
  scope :assigned_to, ->(user_id) { joins(:task_assignees).where(funnel_task_assignees: { user_id: user_id }) }
  # Escopo aplicado ao membro com visibility_scope own_tasks.
  scope :visible_to, lambda { |user_id|
    left_joins(:task_assignees)
      .where('funnel_tasks.created_by_id = :id OR funnel_task_assignees.user_id = :id', id: user_id)
      .distinct
  }

  # O card que representa uma conversa. Havendo cards em quadros diferentes, vale o mais recente:
  # o contrato da Pro carrega um card so, e o ultimo vinculo e o que descreve o atendimento em curso.
  #
  # Mora aqui porque duas coisas precisam concordar sobre "o card desta conversa" — o kanban_task
  # embutido no payload da conversa e o endpoint kanban/conversation_cards. Se cada uma escolhesse
  # sozinha, o agente leria um card e moveria outro, sem erro em lugar nenhum.
  def self.for_conversation(conversation_id)
    task = Funnel::TaskConversation.active
                                   .where(conversation_id: conversation_id)
                                   .order(created_at: :desc)
                                   .first&.task
    return if task.nil? || task.archived_at.present?

    task
  end

  def archived?
    archived_at.present?
  end

  def overdue?
    !archived? && due_at.present? && due_at < Time.current
  end

  def primary_conversation
    task_conversations.find_by(is_primary: true)&.conversation
  end

  # Mesma forma que _task.json.jbuilder desenha, para o navegador poder trocar o card no lugar
  # em vez de recarregar o quadro. Um spec compara as chaves dos dois; se um ganhar campo e o
  # outro nao, ele quebra.
  def push_event_data
    scalar_event_data.merge(step_event_data).merge(association_event_data)
  end

  # O mesmo card que kanban/tasks/_task.json.jbuilder desenha, no contrato da fazer.ai Pro, para
  # viajar tambem no payload de evento da conversa. Um spec compara as chaves dos dois: nomes
  # divergentes dariam ao agente um card pela API e outro pelo webhook, sem erro em lugar nenhum.
  #
  # value sai como string, e nao como BigDecimal: o payload vira argumento de job, e a checagem de
  # argumentos estritos do Sidekiq recusa decimal. Do outro lado nao muda nada — o jbuilder ja
  # serializa BigDecimal como string.
  def kanban_event_data
    {
      id: id,
      board_id: funnel_board_id,
      board_step_id: funnel_step_id,
      title: title,
      description: description,
      priority: priority,
      status: step.stage_type,
      value: value&.to_s,
      start_date: start_at,
      due_date: due_at,
      custom_attributes: custom_attributes,
      labels: labels.map(&:title),
      created_at: created_at,
      updated_at: updated_at,
      board: { id: board.id, name: board.name }
    }
  end

  private

  def scalar_event_data
    {
      id: id, title: title, description: description, priority: priority, value: value&.to_s,
      funnel_board_id: funnel_board_id, funnel_step_id: funnel_step_id, rank: rank.to_s,
      start_at: start_at, due_at: due_at, overdue: overdue?, archived_at: archived_at,
      lock_version: lock_version, custom_attributes: custom_attributes,
      created_at: created_at, updated_at: updated_at, step_changed_at: step_changed_at
    }
  end

  def step_event_data
    { board_name: board.name, step_name: step.name, step_color: step.color, step_stage_type: step.stage_type }
  end

  def association_event_data
    {
      assignees: assignees.map { |user| { id: user.id, name: user.name, avatar_url: user.avatar_url } },
      labels: labels.map { |label| { id: label.id, title: label.title, color: label.color } },
      contacts: contacts.map { |contact| { id: contact.id, name: contact.name } },
      conversations: task_conversations.map do |link|
        { id: link.conversation.display_id, conversation_id: link.conversation_id,
          is_primary: link.is_primary, inbox_id: link.conversation.inbox_id }
      end,
      channel: channel_event_data
    }
  end

  def channel_event_data
    inbox = task_conversations.detect(&:is_primary)&.conversation&.inbox
    return nil if inbox.blank?

    { inbox_id: inbox.id, name: inbox.name, channel_type: inbox.channel_type,
      provider: inbox.channel.try(:provider), medium: inbox.channel.try(:medium) }
  end

  def dispatch_created
    Rails.configuration.dispatcher.dispatch('funnel.task.created', Time.zone.now, task: self)
  end

  # Arquivar e o nosso excluir, e mover e o que o quadro precisa distinguir para animar o card
  # em vez de troca-lo no lugar.
  def dispatch_updated
    event = if saved_change_to_archived_at? && archived_at.present?
              'funnel.task.deleted'
            elsif saved_change_to_funnel_step_id?
              'funnel.task.moved'
            else
              'funnel.task.updated'
            end

    Rails.configuration.dispatcher.dispatch(event, Time.zone.now, task: self)
  end

  def assign_account_from_board
    self.account_id ||= board&.account_id
  end

  # Card novo esta na etapa desde agora; o MoveService reescreve a cada troca.
  def stamp_step_changed_at
    self.step_changed_at ||= Time.current
  end

  def assign_default_rank
    return if rank.present? || funnel_step_id.blank?

    self.rank = Funnel::Ranking.append_after(self.class.where(funnel_step_id: funnel_step_id).maximum(:rank))
  end

  def step_belongs_to_board
    return if step.blank? || board.blank?
    return if step.funnel_board_id == funnel_board_id

    errors.add(:step, 'must belong to the same board as the task')
  end

  def board_belongs_to_account
    return if board.blank? || account_id.blank?
    return if board.account_id == account_id

    errors.add(:board, 'must belong to the same account as the task')
  end

  def conversation_link_columns_changed?
    saved_change_to_archived_at? || saved_change_to_funnel_board_id?
  end

  # Mantem as copias em funnel_task_conversations coerentes com o card. Sao elas que sustentam o
  # unique index parcial de um card ativo por conversa por quadro.
  # update_all e proposital: e uma copia em massa de colunas denormalizadas, nenhuma validacao
  # de TaskConversation depende delas, e o caminho por registro custaria uma query por conversa
  # vinculada so para reescrever dois campos.
  def sync_conversation_link_columns
    # rubocop:disable Rails/SkipsModelValidations
    task_conversations.update_all(active: archived_at.nil?, funnel_board_id: funnel_board_id, updated_at: Time.current)
    # rubocop:enable Rails/SkipsModelValidations
  end
end
