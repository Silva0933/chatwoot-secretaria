# Injetado em Account por Account.include_mod_with('Concerns::Account'), ja presente no core.
# Manter as associacoes do modulo aqui evita tocar em app/models/account.rb e conflitar no
# merge com o upstream.
#
# O toggle do modulo vive em settings jsonb e nao em feature_flags: ver a secao
# "Account-level toggles" do AGENTS.md. A coluna padrao esta cheia (63/63) e as posicoes de bit
# divergem entre main e chatwoot-pro-main, entao uma chave nomeada e imune a esse drift.
#
# O include acontece depois dos store_accessor de Account, entao o super do writer abaixo
# alcanca o modulo gerado pelo store_accessor.
module Custom::Concerns::Account
  extend ActiveSupport::Concern

  included do
    store_accessor :settings, :funnel_kanban_enabled

    has_many :funnel_boards, class_name: 'Funnel::Board', dependent: :destroy_async
    has_many :funnel_tasks, class_name: 'Funnel::Task', dependent: :destroy_async
  end

  # O formulario do superadmin posta "1"/"0" e o JSON schema de settings so aceita boolean.
  def funnel_kanban_enabled=(value)
    super(ActiveModel::Type::Boolean.new.cast(value))
  end

  def funnel_kanban_enabled?
    ActiveModel::Type::Boolean.new.cast(funnel_kanban_enabled).present?
  end
end
