# Cria um quadro com suas etapas iniciais. Sem template informado, usa :clinic.
class Funnel::Boards::CreateService
  # Jornada de paciente, nao funil de vendas. As etapas "Agendado", "Compareceu" e "Faltou"
  # existem desde o MVP porque sao os ganchos onde a Agenda vai plugar na fase seguinte.
  TEMPLATES = {
    clinic: [
      { name: 'Novo contato', color: '#6b7280', stage_type: :open },
      { name: 'Triagem', color: '#3b82f6', stage_type: :open },
      { name: 'Aguardando agendamento', color: '#f59e0b', stage_type: :open },
      { name: 'Agendado', color: '#8b5cf6', stage_type: :open },
      { name: 'Compareceu', color: '#10b981', stage_type: :won },
      { name: 'Pos-atendimento', color: '#14b8a6', stage_type: :open },
      { name: 'Faltou', color: '#ef4444', stage_type: :lost },
      { name: 'Perdido', color: '#991b1b', stage_type: :lost }
    ],
    blank: [
      { name: 'A fazer', color: '#6b7280', stage_type: :open },
      { name: 'Em andamento', color: '#3b82f6', stage_type: :open },
      { name: 'Concluido', color: '#10b981', stage_type: :won }
    ]
  }.freeze

  def initialize(account:, params:, creator: nil, template: :clinic)
    @account = account
    @params = params
    @creator = creator
    @template = template.to_sym
  end

  def perform
    ActiveRecord::Base.transaction do
      board = @account.funnel_boards.create!(@params)
      create_steps(board)
      # Quem cria o quadro entra como manager, senao um administrador que perde o papel de
      # admin ficaria sem acesso ao proprio quadro.
      board.members.create!(user: @creator, role: :manager) if @creator.present?
      board
    end
  end

  private

  def create_steps(board)
    steps = TEMPLATES.fetch(@template, TEMPLATES[:blank])

    steps.each_with_index do |attributes, index|
      board.steps.create!(attributes.merge(rank: Funnel::Ranking::STEP * (index + 1)))
    end
  end
end
