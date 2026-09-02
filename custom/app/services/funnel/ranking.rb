# Ordenacao por rank fracionario. Mover um card entre duas posicoes grava o ponto medio dos
# vizinhos, entao a operacao e um UPDATE de uma linha em vez de reescrever a coluna inteira.
#
# O preco e que o gap entre vizinhos cai pela metade a cada insercao no mesmo ponto. A coluna e
# decimal(30,15), logo ha 15 casas depois da virgula: cerca de 50 insercoes consecutivas no
# mesmo intervalo esgotam a precisao. Quando o gap fica abaixo de MIN_GAP, quem chama deve
# rebalancear a etapa com +rebalance+ antes de gravar.
module Funnel::Ranking
  STEP = BigDecimal('65536')
  MIN_GAP = BigDecimal('0.000000000001') # 1e-12, tres ordens de grandeza acima do limite da coluna

  module_function

  # Rank para inserir entre dois vizinhos. Qualquer um dos lados pode ser nil, o que significa
  # inicio ou fim da lista.
  def between(previous_rank, next_rank)
    return append_after(previous_rank) if next_rank.blank?
    return prepend_before(next_rank) if previous_rank.blank?

    (to_decimal(previous_rank) + to_decimal(next_rank)) / 2
  end

  def append_after(last_rank)
    return STEP if last_rank.blank?

    to_decimal(last_rank) + STEP
  end

  def prepend_before(first_rank)
    return STEP if first_rank.blank?

    to_decimal(first_rank) - STEP
  end

  # true quando os vizinhos estao proximos demais para caber outro ponto medio com seguranca.
  def rebalance_needed?(previous_rank, next_rank)
    return false if previous_rank.blank? || next_rank.blank?

    (to_decimal(next_rank) - to_decimal(previous_rank)).abs < MIN_GAP
  end

  # Redistribui os ranks em intervalos de STEP preservando a ordem atual.
  # Recebe os ids ja na ordem desejada e devolve o mapa id => novo rank.
  def rebalance(ordered_ids)
    ordered_ids.each_with_index.to_h { |id, index| [id, STEP * (index + 1)] }
  end

  def to_decimal(value)
    value.is_a?(BigDecimal) ? value : BigDecimal(value.to_s)
  end
end
