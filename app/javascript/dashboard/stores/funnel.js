import camelcaseKeys from 'camelcase-keys';
import snakecaseKeys from 'snakecase-keys';
import { defineStore } from 'pinia';
import FunnelBoardsApi from 'dashboard/api/funnel/boards';
import FunnelConversationTasksApi from 'dashboard/api/funnel/conversationTasks';
import FunnelReportsApi from 'dashboard/api/funnel/reports';
import FunnelStepsApi from 'dashboard/api/funnel/steps';
import FunnelTasksApi from 'dashboard/api/funnel/tasks';
import { throwErrorMessage } from 'dashboard/store/utils/api';
import {
  sortByRank,
  groupTasksByStep,
  filterTasks,
  hasActiveFilters,
  EMPTY_FILTERS,
} from 'dashboard/helper/funnelHelper';

const createUIFlags = () => ({
  fetchingBoards: false,
  creatingBoard: false,
  updatingBoard: false,
  fetchingTasks: false,
  creatingTask: false,
  updatingTask: false,
  movingTask: false,
  updatingAssociations: false,
  savingStep: false,
  savingBoardSettings: false,
  fetchingConversationTasks: false,
  fetchingReport: false,
  fetchingEvents: false,
});

// stopPaths em custom_attributes: as chaves ali sao do cliente, camelizar renomearia dado dele.
const camelize = data =>
  camelcaseKeys(data ?? {}, { deep: true, stopPaths: ['custom_attributes'] });

const buildTaskPayload = ({ customAttributes, ...rest } = {}) => ({
  task: {
    ...snakecaseKeys(rest, { deep: true }),
    ...(customAttributes ? { custom_attributes: customAttributes } : {}),
  },
});

export const useFunnelStore = defineStore('funnel', {
  state: () => ({
    boards: [],
    tasks: [],
    activeBoardId: null,
    taskEvents: [],
    conversationTasks: [],
    report: null,
    filters: { ...EMPTY_FILTERS },
    sortBy: 'position',
    uiFlags: createUIFlags(),
  }),

  getters: {
    getBoards: state => state.boards,

    getActiveBoard: state =>
      state.boards.find(board => board.id === state.activeBoardId) || null,

    getSteps() {
      return sortByRank(this.getActiveBoard?.steps ?? []);
    },

    getFilteredTasks: state => filterTasks(state.tasks, state.filters),

    // Um unico agrupamento memoizado alimenta todas as colunas; um getter por coluna
    // reordenaria a lista inteira uma vez por etapa a cada arrasto.
    getTasksByStep() {
      return groupTasksByStep(
        this.getSteps,
        this.getFilteredTasks,
        this.sortBy
      );
    },

    // Total ponderado: cada card pesa o proprio valor vezes a probabilidade da etapa onde esta.
    // Respeita o filtro, como o relatorio pede dos contadores.
    getPipelineValue() {
      const steps = Object.fromEntries(
        this.getSteps.map(step => [step.id, (step.probability ?? 0) / 100])
      );

      return this.getFilteredTasks.reduce(
        (total, task) =>
          total + Number(task.value ?? 0) * (steps[task.funnelStepId] ?? 0),
        0
      );
    },

    hasFilters: state => hasActiveFilters(state.filters),

    // Arrastar so faz sentido na ordem por posicao. Nas outras a lista na tela nao reflete o
    // rank, entao os vizinhos que o arrasto informaria dariam uma posicao sem relacao com o que
    // o usuario viu — o card pareceria pular de lugar ao voltar para a ordem por posicao.
    canReorder: state => state.sortBy === 'position',

    getUIFlags: state => state.uiFlags,

    getTask: state => id => state.tasks.find(task => task.id === Number(id)),
  },

  actions: {
    setUIFlag(flags) {
      this.uiFlags = { ...this.uiFlags, ...flags };
    },

    upsertBoard(board) {
      const index = this.boards.findIndex(item => item.id === board.id);
      if (index === -1) this.boards.push(board);
      else this.boards[index] = board;
    },

    upsertTask(task) {
      const index = this.tasks.findIndex(item => item.id === task.id);
      if (index === -1) this.tasks.push(task);
      else this.tasks[index] = task;
    },

    removeTask(id) {
      this.tasks = this.tasks.filter(task => task.id !== Number(id));
    },

    setActiveBoardId(boardId) {
      const id = boardId ? Number(boardId) : null;
      if (this.activeBoardId === id) return;

      this.activeBoardId = id;
      this.tasks = [];
    },

    async fetchBoards() {
      this.setUIFlag({ fetchingBoards: true });
      try {
        const { data } = await FunnelBoardsApi.get();
        this.boards = camelize(data.payload ?? data);
        return this.boards;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.setUIFlag({ fetchingBoards: false });
      }
    },

    async createBoard({ name, description, template }) {
      this.setUIFlag({ creatingBoard: true });
      try {
        const { data } = await FunnelBoardsApi.create({
          board: { name, description },
          template,
        });
        const board = camelize(data.payload ?? data);
        this.upsertBoard(board);
        return board;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.setUIFlag({ creatingBoard: false });
      }
    },

    async updateBoard({ id, name, description }) {
      this.setUIFlag({ updatingBoard: true });
      try {
        const { data } = await FunnelBoardsApi.update(id, {
          board: { name, description },
        });
        const board = camelize(data.payload ?? data);
        this.upsertBoard(board);
        return board;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.setUIFlag({ updatingBoard: false });
      }
    },

    // Arquivar, nao excluir: o backend so marca archived_at para preservar o historico.
    async archiveBoard(id) {
      this.setUIFlag({ updatingBoard: true });
      try {
        await FunnelBoardsApi.delete(id);
        this.boards = this.boards.filter(board => board.id !== Number(id));
        if (this.activeBoardId === Number(id)) this.setActiveBoardId(null);
        return Number(id);
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.setUIFlag({ updatingBoard: false });
      }
    },

    /**
     * Toda acao de etapa devolve o quadro inteiro, porque mexer numa coluna muda a ordem, a cor
     * ou a existencia das outras. Recarrega os cards depois de excluir: os que estavam na etapa
     * que saiu foram realocados pelo servidor.
     */
    async saveStep({ id, boardId = this.activeBoardId, ...attributes }) {
      this.setUIFlag({ savingStep: true });
      try {
        const payload = {
          name: attributes.name,
          color: attributes.color,
          stage_type: attributes.stageType,
          probability: attributes.probability,
        };
        const { data } = id
          ? await FunnelStepsApi.update(boardId, id, payload)
          : await FunnelStepsApi.create(boardId, payload);
        this.upsertBoard(camelize(data.payload ?? data));
        return this.getActiveBoard;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.setUIFlag({ savingStep: false });
      }
    },

    async deleteStep({
      id,
      targetStepId = null,
      boardId = this.activeBoardId,
    }) {
      this.setUIFlag({ savingStep: true });
      try {
        const { data } = await FunnelStepsApi.delete(boardId, id, targetStepId);
        this.upsertBoard(camelize(data.payload ?? data));
        await this.fetchTasks(boardId);
        return this.getActiveBoard;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.setUIFlag({ savingStep: false });
      }
    },

    async replaceBoardMembers({ boardId = this.activeBoardId, members }) {
      this.setUIFlag({ savingBoardSettings: true });
      try {
        const { data } = await FunnelBoardsApi.replaceMembers(boardId, members);
        this.upsertBoard(camelize(data.payload ?? data));
        return this.getActiveBoard;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.setUIFlag({ savingBoardSettings: false });
      }
    },

    async replaceBoardInboxes({ boardId = this.activeBoardId, inboxIds }) {
      this.setUIFlag({ savingBoardSettings: true });
      try {
        const { data } = await FunnelBoardsApi.replaceInboxes(
          boardId,
          inboxIds
        );
        this.upsertBoard(camelize(data.payload ?? data));
        return this.getActiveBoard;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.setUIFlag({ savingBoardSettings: false });
      }
    },

    // A ordem final das etapas, como o arrasto deixou. Poucas colunas, entao reescrever todos os
    // ranks e barato — ao contrario dos cards, onde o rank fracionario existe para evitar isso.
    async reorderSteps({ boardId = this.activeBoardId, stepIds }) {
      this.setUIFlag({ savingStep: true });
      try {
        const { data } = await FunnelStepsApi.reorder(boardId, stepIds);
        this.upsertBoard(camelize(data.payload ?? data));
        return this.getActiveBoard;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.setUIFlag({ savingStep: false });
      }
    },

    async fetchTasks(boardId = this.activeBoardId) {
      if (!boardId) return [];

      this.setUIFlag({ fetchingTasks: true });
      // A resposta lenta de um quadro que o usuario ja trocou nao pode sobrescrever a lista
      // do quadro atual.
      const requestedBoardId = Number(boardId);
      try {
        const { data } = await FunnelTasksApi.get(requestedBoardId);
        const tasks = camelize(data.payload ?? data);
        if (this.activeBoardId === requestedBoardId) this.tasks = tasks;
        return tasks;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        if (this.activeBoardId === requestedBoardId) {
          this.setUIFlag({ fetchingTasks: false });
        }
      }
    },

    async createTask({ boardId = this.activeBoardId, ...attributes }) {
      this.setUIFlag({ creatingTask: true });
      try {
        const { data } = await FunnelTasksApi.create(
          boardId,
          buildTaskPayload(attributes)
        );
        const task = camelize(data.payload ?? data);
        if (this.activeBoardId === Number(boardId)) this.upsertTask(task);
        return task;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.setUIFlag({ creatingTask: false });
      }
    },

    async updateTask({ id, boardId = this.activeBoardId, ...attributes }) {
      this.setUIFlag({ updatingTask: true });
      try {
        const { data } = await FunnelTasksApi.update(
          boardId,
          id,
          buildTaskPayload(attributes)
        );
        const task = camelize(data.payload ?? data);
        this.upsertTask(task);
        return task;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.setUIFlag({ updatingTask: false });
      }
    },

    async archiveTask({ id, boardId = this.activeBoardId }) {
      this.setUIFlag({ updatingTask: true });
      try {
        await FunnelTasksApi.delete(boardId, id);
        this.removeTask(id);
        return Number(id);
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.setUIFlag({ updatingTask: false });
      }
    },

    /**
     * O quadro ja moveu o card na tela antes de chamar aqui. Se a API recusar, o unico
     * jeito honesto de voltar e reler a lista: o rank que o servidor gravou depende de quem
     * mais moveu cards no intervalo, entao um rollback local sairia errado.
     */
    async moveTask({
      id,
      stepId,
      afterId,
      beforeId,
      boardId = this.activeBoardId,
    }) {
      this.setUIFlag({ movingTask: true });
      try {
        const { data } = await FunnelTasksApi.move(boardId, id, {
          stepId,
          afterId,
          beforeId,
        });
        const task = camelize(data.payload ?? data);
        this.upsertTask(task);
        return task;
      } catch (error) {
        await this.fetchTasks(boardId).catch(() => {});
        return throwErrorMessage(error);
      } finally {
        this.setUIFlag({ movingTask: false });
      }
    },

    /**
     * Responsaveis, etiquetas e contatos sao gravados na hora, um endpoint por conjunto, em vez
     * de entrarem no submit do formulario: sao listas independentes e a resposta ja devolve o
     * card inteiro atualizado, entao nao ha o que reconciliar.
     */
    async replaceAssociation({ id, kind, ids, boardId = this.activeBoardId }) {
      const call = {
        assignees: FunnelTasksApi.replaceAssignees,
        labels: FunnelTasksApi.replaceLabels,
        contacts: FunnelTasksApi.replaceContacts,
      }[kind];

      this.setUIFlag({ updatingAssociations: true });
      try {
        const { data } = await call.call(FunnelTasksApi, boardId, id, ids);
        const task = camelize(data.payload ?? data);
        this.upsertTask(task);
        return task;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.setUIFlag({ updatingAssociations: false });
      }
    },

    async linkConversation({ id, displayId, boardId = this.activeBoardId }) {
      this.setUIFlag({ updatingAssociations: true });
      try {
        const { data } = await FunnelTasksApi.linkConversation(
          boardId,
          id,
          displayId
        );
        const task = camelize(data.payload ?? data);
        this.upsertTask(task);
        return task;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.setUIFlag({ updatingAssociations: false });
      }
    },

    async promoteConversation({ id, displayId, boardId = this.activeBoardId }) {
      this.setUIFlag({ updatingAssociations: true });
      try {
        const { data } = await FunnelTasksApi.promoteConversation(
          boardId,
          id,
          displayId
        );
        const task = camelize(data.payload ?? data);
        this.upsertTask(task);
        return task;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.setUIFlag({ updatingAssociations: false });
      }
    },

    async unlinkConversation({ id, displayId, boardId = this.activeBoardId }) {
      this.setUIFlag({ updatingAssociations: true });
      try {
        const { data } = await FunnelTasksApi.unlinkConversation(
          boardId,
          id,
          displayId
        );
        const task = camelize(data.payload ?? data);
        this.upsertTask(task);
        return task;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.setUIFlag({ updatingAssociations: false });
      }
    },

    async fetchTaskEvents({ id, boardId = this.activeBoardId }) {
      this.setUIFlag({ fetchingEvents: true });
      try {
        const { data } = await FunnelTasksApi.events(boardId, id);
        this.taskEvents = camelize(data.payload ?? data);
        return this.taskEvents;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.setUIFlag({ fetchingEvents: false });
      }
    },

    clearTaskEvents() {
      this.taskEvents = [];
    },

    /**
     * Cards ligados a uma conversa. Lista separada de `tasks` de proposito: aquela e o quadro
     * aberto, esta e o painel da conversa, e os dois podem estar em quadros diferentes na tela
     * ao mesmo tempo.
     */
    async fetchConversationTasks(conversationId) {
      this.setUIFlag({ fetchingConversationTasks: true });
      try {
        const { data } = await FunnelConversationTasksApi.get(conversationId);
        this.conversationTasks = camelize(data.payload ?? data);
        return this.conversationTasks;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.setUIFlag({ fetchingConversationTasks: false });
      }
    },

    async createTaskFromConversation({
      conversationId,
      boardId,
      funnelStepId = null,
    }) {
      this.setUIFlag({ creatingTask: true });
      try {
        const { data } = await FunnelConversationTasksApi.create(
          conversationId,
          {
            boardId,
            funnelStepId,
          }
        );
        const task = camelize(data.payload ?? data);
        this.conversationTasks = [...this.conversationTasks, task];
        // O quadro aberto noutra aba precisa do card novo se for o mesmo quadro.
        if (this.activeBoardId === task.funnelBoardId) this.upsertTask(task);
        return task;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.setUIFlag({ creatingTask: false });
      }
    },

    /**
     * Move sem ancora: da conversa nao ha vizinhos para escolher, e o card vai para o fim da
     * etapa de destino, que e o que o MoveService faz quando after_id e before_id vem vazios.
     */
    async moveConversationTask({ id, boardId, stepId, conversationId }) {
      this.setUIFlag({ movingTask: true });
      try {
        const { data } = await FunnelTasksApi.move(boardId, id, {
          stepId,
          afterId: null,
          beforeId: null,
        });
        const task = camelize(data.payload ?? data);
        this.conversationTasks = this.conversationTasks.map(item =>
          item.id === task.id ? task : item
        );
        if (this.activeBoardId === task.funnelBoardId) this.upsertTask(task);
        return task;
      } catch (error) {
        await this.fetchConversationTasks(conversationId).catch(() => {});
        return throwErrorMessage(error);
      } finally {
        this.setUIFlag({ movingTask: false });
      }
    },

    setFilters(filters) {
      this.filters = { ...this.filters, ...filters };
    },

    clearFilters() {
      this.filters = { ...EMPTY_FILTERS };
    },

    setSortBy(sortBy) {
      this.sortBy = sortBy;
    },

    /**
     * Eventos do websocket. Chegam para quem tem o quadro aberto, entao o primeiro cuidado e
     * ignorar o que nao e do quadro em foco: um agente pode estar vendo o funil comercial
     * enquanto outro mexe no de pos-atendimento.
     *
     * Nao ha reconciliacao com escrita local pendente porque nao existe: as acoes daqui so
     * gravam na store depois da resposta do servidor, entao o evento sempre chega sobre um
     * estado ja confirmado.
     */
    applyRemoteTask(payload) {
      if (!payload || payload.funnelBoardId !== this.activeBoardId) return;

      this.upsertTask(payload);
    },

    applyRemoteTaskRemoval(payload) {
      if (!payload || payload.funnelBoardId !== this.activeBoardId) return;

      this.removeTask(payload.id);
    },

    // O quadro chega inteiro porque mexer numa etapa reordena ou recolore as outras. Os cards
    // nao vem junto: eles tem eventos proprios, e reenvia-los a cada renomeacao de coluna
    // mandaria o quadro todo pelo websocket a cada tecla do formulario de etapa.
    applyRemoteBoard(payload) {
      if (!payload) return;

      const index = this.boards.findIndex(board => board.id === payload.id);
      if (index === -1) return;

      this.boards[index] = { ...this.boards[index], ...payload };
    },

    async fetchReport({
      boardId = this.activeBoardId,
      since = null,
      until = null,
    } = {}) {
      if (!boardId) return null;

      this.setUIFlag({ fetchingReport: true });
      try {
        const { data } = await FunnelReportsApi.get(boardId, { since, until });
        this.report = camelize(data.payload ?? data);
        return this.report;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.setUIFlag({ fetchingReport: false });
      }
    },

    reset() {
      this.boards = [];
      this.tasks = [];
      this.taskEvents = [];
      this.conversationTasks = [];
      this.report = null;
      this.filters = { ...EMPTY_FILTERS };
      this.sortBy = 'position';
      this.activeBoardId = null;
      this.uiFlags = createUIFlags();
    },
  },
});
