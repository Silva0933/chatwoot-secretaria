/* global axios */
import ApiClient from '../ApiClient';

class FunnelReportsAPI extends ApiClient {
  constructor() {
    super('funnel/boards', { accountScoped: true });
  }

  reportUrl(boardId) {
    return `${this.url}/${boardId}/report`;
  }

  get(boardId, { since, until } = {}) {
    return axios.get(this.reportUrl(boardId), { params: { since, until } });
  }

  // A exportacao nao passa pelo axios: o navegador baixando direto poupa carregar o CSV inteiro
  // em memoria so para reemiti-lo como blob.
  exportUrl(boardId, { since, until } = {}) {
    const params = new URLSearchParams({
      ...(since ? { since } : {}),
      ...(until ? { until } : {}),
    });

    return `${this.reportUrl(boardId)}.csv?${params.toString()}`;
  }
}

export default new FunnelReportsAPI();
