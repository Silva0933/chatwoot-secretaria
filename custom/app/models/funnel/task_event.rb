class Funnel::TaskEvent < ApplicationRecord
  belongs_to :task, class_name: 'Funnel::Task', foreign_key: :funnel_task_id, inverse_of: :events
  belongs_to :account
  belongs_to :actor, polymorphic: true, optional: true

  # created_at e gravado na mao porque a tabela nao tem updated_at: evento de auditoria nao muda.
  before_validation :stamp_created_at, on: :create

  validates :event_type, presence: true

  # "agent" e a IA de atendimento movendo o card por conta propria, e vale a categoria propria em
  # vez de cair em "api": ela chama a API com o mesmo token de um administrador, entao o ator
  # gravado nao a distingue de uma pessoa. A pergunta que alguem faz olhando um card que andou
  # sozinho e exatamente essa, e sem o rotulo o registro nao a responde.
  SOURCES = %w[web api automation agent system].freeze
  validates :source, inclusion: { in: SOURCES }

  private

  def stamp_created_at
    self.created_at ||= Time.current
  end
end
