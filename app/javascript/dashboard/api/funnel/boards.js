import ApiClient from '../ApiClient';

class FunnelBoardsAPI extends ApiClient {
  constructor() {
    super('funnel/boards', { accountScoped: true });
  }
}

export default new FunnelBoardsAPI();
