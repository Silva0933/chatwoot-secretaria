/* global axios */
import ApiClient from '../ApiClient';

// As etapas pertencem ao quadro e todas as acoes devolvem o quadro inteiro: mudar uma coluna
// reordena ou recolore o resto da tela, entao devolver so a etapa obrigaria o cliente a
// remontar o quadro a mao.
class FunnelStepsAPI extends ApiClient {
  constructor() {
    super('funnel/boards', { accountScoped: true });
  }

  stepsUrl(boardId) {
    return `${this.url}/${boardId}/steps`;
  }

  create(boardId, step) {
    return axios.post(this.stepsUrl(boardId), { step });
  }

  update(boardId, id, step) {
    return axios.patch(`${this.stepsUrl(boardId)}/${id}`, { step });
  }

  // targetStepId diz para onde vao os cards da etapa que sai; sem ele o backend usa a primeira.
  delete(boardId, id, targetStepId = null) {
    return axios.delete(`${this.stepsUrl(boardId)}/${id}`, {
      data: targetStepId ? { target_step_id: targetStepId } : {},
    });
  }

  reorder(boardId, stepIds) {
    return axios.patch(`${this.stepsUrl(boardId)}/reorder`, {
      step_ids: stepIds,
    });
  }
}

export default new FunnelStepsAPI();
