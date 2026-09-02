/* global axios */
import ApiClient from '../ApiClient';

// O id na rota e o display_id da conversa, o numero que o agente ve no Chatwoot.
class FunnelConversationTasksAPI extends ApiClient {
  constructor() {
    super('funnel/conversations', { accountScoped: true });
  }

  tasksUrl(conversationId) {
    return `${this.url}/${conversationId}/tasks`;
  }

  get(conversationId) {
    return axios.get(this.tasksUrl(conversationId));
  }

  create(conversationId, { boardId, funnelStepId = null, task = {} }) {
    return axios.post(this.tasksUrl(conversationId), {
      board_id: boardId,
      funnel_step_id: funnelStepId,
      task,
    });
  }
}

export default new FunnelConversationTasksAPI();
