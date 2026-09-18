# Registra o listener do Funnel sem tocar no core: SyncDispatcher termina com
# prepend_mod_with('SyncDispatcher'), que e exatamente este gancho.
#
# Sincrono e nao assincrono de proposito. O quadro aberto de outro atendente precisa reagir no
# mesmo instante; passar pela fila colocaria o redesenho atras do Sidekiq, que na pratica e onde
# esta a lentidao percebida como "o Kanban nao atualiza".
module Custom::SyncDispatcher
  def listeners
    super + [FunnelListener.instance]
  end
end
