# Relatorio do funil, em JSON para a tela e em CSV para quem quer levar para a planilha.
class Api::V1::Accounts::Funnel::ReportsController < Api::V1::Accounts::Funnel::BaseController
  before_action :fetch_board
  before_action :check_authorization

  def show
    @report = build_report

    respond_to do |format|
      format.json { render :show }
      format.csv { send_data to_csv, filename: csv_filename, type: 'text/csv' }
    end
  end

  private

  def fetch_board
    @board = Current.account.funnel_boards.find(params[:board_id])
  end

  # Ver o relatorio exige ver o quadro. Os numeros ja saem restritos pelo policy_scope: um
  # membro limitado aos proprios cards le um relatorio dos proprios cards.
  def check_authorization
    authorize(@board, :show?)
  end

  def build_report
    Funnel::Reports::BoardReport.new(
      board: @board,
      scope: policy_scope(Funnel::Task.where(account_id: Current.account.id)),
      since: parse_time(params[:since]),
      until_time: parse_time(params[:until])
    ).perform
  end

  def parse_time(value)
    return nil if value.blank?

    Time.zone.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  # Uma linha por etapa: e o recorte que responde "onde meu funil esta preso", que e a pergunta
  # que leva alguem a exportar. Os totais vao no cabecalho para o arquivo se explicar sozinho.
  def to_csv
    CSV.generate(headers: true) do |csv|
      csv_header_rows.each { |row| csv << row }
      csv << ['Etapa', 'Tipo', 'Cards', 'Valor', 'Idade mediana (dias)', 'Parados']
      @report[:steps].each { |step| csv << step_row(step) }
    end
  end

  def csv_header_rows
    totals = @report[:totals]
    range = @report[:range]

    [
      ['Quadro', @board.name],
      ['Periodo', range[:since].to_date.to_s, range[:until].to_date.to_s],
      ['Criados', totals[:created]],
      ['Ganhos', totals[:won]],
      ['Perdidos', totals[:lost]],
      ['Taxa de ganho (%)', totals[:win_rate]],
      []
    ]
  end

  def step_row(step)
    median_days = step[:median_age_seconds] ? (step[:median_age_seconds] / 86_400.0).round(1) : nil
    [step[:name], step[:stage_type], step[:count], step[:value], median_days, step[:stalled_count]]
  end

  def csv_filename
    "funil-#{@board.name.parameterize}-#{Date.current}.csv"
  end
end
