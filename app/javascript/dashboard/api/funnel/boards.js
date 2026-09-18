/* global axios */
import ApiClient from '../ApiClient';

class FunnelBoardsAPI extends ApiClient {
  constructor() {
    super('funnel/boards', { accountScoped: true });
  }

  // Membros e caixas devolvem o quadro inteiro: mudar quem participa muda as permissoes que o
  // proprio payload do quadro carrega.
  replaceMembers(boardId, members) {
    return axios.put(`${this.url}/${boardId}/members`, { members });
  }

  replaceInboxes(boardId, inboxIds) {
    return axios.put(`${this.url}/${boardId}/inboxes`, { inbox_ids: inboxIds });
  }
}

export default new FunnelBoardsAPI();
