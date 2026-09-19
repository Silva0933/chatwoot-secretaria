# O trecho que o card mostra: a ultima mensagem DO CLIENTE em cada conversa.
#
# Do cliente, e nao a ultima de quem for. As duas respondem perguntas diferentes: a ultima
# mensagem da conversa e quase sempre a resposta do agente ("ja estou preparando a proposta"),
# que quem le o quadro escreveu e ja sabe. O que ele nao sabe de relance e o que o cliente pediu.
#
# Uma consulta so para o quadro inteiro. O DISTINCT ON do Postgres devolve uma linha por
# conversa, a mais recente; a alternativa seria uma consulta por card, e um quadro com
# trezentos cards abriria trezentas.
class Funnel::ConversationPreviews
  # Duas linhas no card cabem folgadas em 240 caracteres. Cortar aqui e nao no navegador evita
  # mandar o corpo inteiro de uma mensagem longa para cada card do quadro.
  EXCERPT_LIMIT = 240

  def initialize(conversation_ids)
    @conversation_ids = Array(conversation_ids).compact.uniq
  end

  def perform
    return {} if @conversation_ids.empty?

    # reorder e nao order: Message tem default_scope { order(created_at: :asc) }, e o Postgres
    # exige que o ORDER BY comece exatamente pelas expressoes do DISTINCT ON. Encadeando order,
    # o created_at do default_scope entraria na frente de conversation_id e a consulta estouraria
    # em toda carga do quadro.
    #
    # Mensagem so com anexo tem content nulo e fica de fora: o card mostraria uma linha vazia, e
    # a ultima frase que o cliente escreveu informa mais do que nada.
    Message.where(conversation_id: @conversation_ids, message_type: :incoming, private: false)
           .where.not(content: nil)
           .where.not(content: '')
           .select('DISTINCT ON (conversation_id) conversation_id, content')
           .reorder('conversation_id, created_at DESC, id DESC')
           .each_with_object({}) { |message, previews| previews[message.conversation_id] = message.content.truncate(EXCERPT_LIMIT) }
  end
end
