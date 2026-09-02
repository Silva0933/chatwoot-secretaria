/* global axios */
import ApiClient from '../ApiClient';

// Os cards vivem sob o quadro (/funnel/boards/:boardId/tasks), entao boardId entra em toda
// chamada em vez de virar estado do cliente: o mesmo cliente serve dois quadros abertos.
class FunnelTasksAPI extends ApiClient {
  constructor() {
    super('funnel/boards', { accountScoped: true });
  }

  tasksUrl(boardId) {
    return `${this.url}/${boardId}/tasks`;
  }

  get(boardId) {
    return axios.get(this.tasksUrl(boardId));
  }

  show(boardId, id) {
    return axios.get(`${this.tasksUrl(boardId)}/${id}`);
  }

  create(boardId, data) {
    return axios.post(this.tasksUrl(boardId), data);
  }

  update(boardId, id, data) {
    return axios.patch(`${this.tasksUrl(boardId)}/${id}`, data);
  }

  delete(boardId, id) {
    return axios.delete(`${this.tasksUrl(boardId)}/${id}`);
  }

  // Posicao vai como os ids dos vizinhos, nunca como indice: ver Funnel::Tasks::MoveService.
  move(boardId, id, { stepId, afterId, beforeId }) {
    return axios.patch(`${this.tasksUrl(boardId)}/${id}/move`, {
      step_id: stepId,
      after_id: afterId,
      before_id: beforeId,
    });
  }

  // PUT troca o conjunto inteiro: o multiselect do card sabe o estado final, nao o delta.
  replaceAssignees(boardId, id, userIds) {
    return axios.put(`${this.tasksUrl(boardId)}/${id}/assignees`, {
      user_ids: userIds,
    });
  }

  replaceLabels(boardId, id, labelIds) {
    return axios.put(`${this.tasksUrl(boardId)}/${id}/labels`, {
      label_ids: labelIds,
    });
  }

  replaceContacts(boardId, id, contactIds) {
    return axios.put(`${this.tasksUrl(boardId)}/${id}/contacts`, {
      contact_ids: contactIds,
    });
  }

  // displayId e o numero da conversa que o agente ve no Chatwoot, nao o id interno.
  linkConversation(boardId, id, displayId) {
    return axios.post(`${this.tasksUrl(boardId)}/${id}/conversations`, {
      conversation_id: displayId,
    });
  }

  promoteConversation(boardId, id, displayId) {
    return axios.patch(
      `${this.tasksUrl(boardId)}/${id}/conversations/${displayId}`
    );
  }

  unlinkConversation(boardId, id, displayId) {
    return axios.delete(
      `${this.tasksUrl(boardId)}/${id}/conversations/${displayId}`
    );
  }

  events(boardId, id) {
    return axios.get(`${this.tasksUrl(boardId)}/${id}/events`);
  }
}

export default new FunnelTasksAPI();
