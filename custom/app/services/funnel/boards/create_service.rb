# Cria um quadro com suas etapas iniciais. Sem template informado, usa :clinic.
class Funnel::Boards::CreateService
  # Jornada de paciente, nao funil de vendas. As etapas "Agendado", "Compareceu" e "Faltou"
  # existem desde o MVP porque sao os ganchos onde a Agenda vai plugar na fase seguinte.
  #
  # As cores sao as mesmas seis do seletor de etapa (STEP_COLORS em funnelHelper.js), medidas com
  # o validador de contraste. Antes os templates usavam uma paleta propria, que divergia da do
  # seletor: um quadro nascia com turquesa e violeta, e quem fosse editar a etapa nao achava
  # aquelas cores na lista. Seis cores para oito etapas repete de proposito — a cor agrupa, o nome
  # identifica, e o icone diz o que e ganho e o que e perdido.
  TEMPLATES = {
    clinic: [
      { name: 'Novo contato', color: '#64748B', stage_type: :open },
      { name: 'Triagem', color: '#2D8FE0', stage_type: :open },
      { name: 'Aguardando agendamento', color: '#C77D11', stage_type: :open },
      { name: 'Agendado', color: '#D6409F', stage_type: :open },
      { name: 'Compareceu', color: '#2E9E5B', stage_type: :won },
      { name: 'Pos-atendimento', color: '#2D8FE0', stage_type: :open },
      { name: 'Faltou', color: '#E5484D', stage_type: :lost },
      { name: 'Perdido', color: '#E5484D', stage_type: :lost }
    ],
    blank: [
      { name: 'A fazer', color: '#64748B', stage_type: :open },
      { name: 'Em andamento', color: '#2D8FE0', stage_type: :open },
      { name: 'Concluido', color: '#2E9E5B', stage_type: :won }
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
