import camelcaseKeys from 'camelcase-keys';
import snakecaseKeys from 'snakecase-keys';
import { defineStore } from 'pinia';
import FunnelBoardsApi from 'dashboard/api/funnel/boards';
import FunnelTasksApi from 'dashboard/api/funnel/tasks';
import { throwErrorMessage } from 'dashboard/store/utils/api';
import { sortByRank, groupTasksByStep } from 'dashboard/helper/funnelHelper';

const createUIFlags = () => ({
  fetchingBoards: false,
  creatingBoard: false,
  updatingBoard: false,
  fetchingTasks: false,
  creatingTask: false,
  updatingTask: false,
  movingTask: false,
  updatingAssociations: false,
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
    uiFlags: createUIFlags(),
  }),

  getters: {
    getBoards: state => state.boards,

    getActiveBoard: state =>
      state.boards.find(board => board.id === state.activeBoardId) || null,

    getSteps() {
      return sortByRank(this.getActiveBoard?.steps ?? []);
    },

    // Um unico agrupamento memoizado alimenta todas as colunas; um getter por coluna
    // reordenaria a lista inteira uma vez por etapa a cada arrasto.
    getTasksByStep() {
      return groupTasksByStep(this.getSteps, this.tasks);
    },

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

    reset() {
      this.boards = [];
      this.tasks = [];
      this.taskEvents = [];
      this.activeBoardId = null;
      this.uiFlags = createUIFlags();
    },
  },
});
