# Automacoes entram no dispatcher assincrono, e nao no sincrono como o FunnelListener.
#
# A diferenca e o que cada um faz: o FunnelListener empurra pixel para o navegador e precisa ser
# imediato; este cria card, move etapa e resolve conversa — escritas que nao devem pendurar a
# requisicao de quem mandou a mensagem.
module Custom::AsyncDispatcher
  def listeners
    super + [FunnelAutomationListener.instance]
  end
end
