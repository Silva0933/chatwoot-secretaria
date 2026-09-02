<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { OnClickOutside } from '@vueuse/components';

import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useFunnelStore } from 'dashboard/stores/funnel';

import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import BoardCreateDialog from '../components/BoardCreateDialog.vue';
import FunnelBoardCanvas from '../components/FunnelBoardCanvas.vue';
import TaskDialog from '../components/TaskDialog.vue';

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const funnelStore = useFunnelStore();
const store = useStore();
const { currentAccount } = useAccount();

const currentRole = useMapGetter('getCurrentRole');

const boardCreateDialogRef = ref(null);
const taskDialogRef = ref(null);
const archiveBoardDialogRef = ref(null);
const archiveTaskDialogRef = ref(null);
const showBoardSwitcher = ref(false);
const taskPendingArchive = ref(null);

const isModuleEnabled = computed(() =>
  Boolean(currentAccount.value?.settings?.funnel_kanban_enabled)
);

const boards = computed(() => funnelStore.getBoards);
const activeBoard = computed(() => funnelStore.getActiveBoard);
const steps = computed(() => funnelStore.getSteps);
const tasksByStep = computed(() => funnelStore.getTasksByStep);
const uiFlags = computed(() => funnelStore.getUIFlags);

const isAdministrator = computed(() => currentRole.value === 'administrator');
const canCreateTask = computed(
  () => activeBoard.value?.permissions?.createTask ?? false
);
const canManageBoard = computed(
  () => activeBoard.value?.permissions?.manageBoard ?? false
);

const isLoadingBoard = computed(
  () => uiFlags.value.fetchingBoards || uiFlags.value.fetchingTasks
);
const isSavingTask = computed(
  () => uiFlags.value.creatingTask || uiFlags.value.updatingTask
);

const boardMenuItems = computed(() =>
  boards.value.map(board => ({
    label: board.name,
    value: board.id,
    action: 'switch',
    isSelected: board.id === activeBoard.value?.id,
  }))
);

const syncBoardInUrl = boardId => {
  if (Number(route.query.board) === Number(boardId)) return;

  router.replace({
    name: route.name,
    params: route.params,
    query: { ...route.query, board: boardId ? String(boardId) : undefined },
  });
};

const selectBoard = async boardId => {
  funnelStore.setActiveBoardId(boardId);
  syncBoardInUrl(boardId);
  if (!boardId) return;

  try {
    await funnelStore.fetchTasks(boardId);
  } catch (error) {
    useAlert(error.message || t('FUNNEL.API.TASKS_ERROR'));
  }
};

const loadBoards = async () => {
  try {
    await funnelStore.fetchBoards();
  } catch (error) {
    useAlert(error.message || t('FUNNEL.API.BOARDS_ERROR'));
    return;
  }

  // Um id na URL que nao existe mais (quadro arquivado, link antigo) cai no primeiro quadro
  // em vez de deixar a tela vazia sem explicacao.
  const requestedId = Number(route.query.board);
  const requested = boards.value.find(board => board.id === requestedId);
  await selectBoard((requested ?? boards.value[0])?.id ?? null);
};

const toggleBoardSwitcher = () => {
  showBoardSwitcher.value = !showBoardSwitcher.value;
};

const onBoardMenuAction = ({ value }) => {
  showBoardSwitcher.value = false;
  selectBoard(value);
};

const onCreateBoard = async payload => {
  try {
    const board = await funnelStore.createBoard(payload);
    boardCreateDialogRef.value?.close();
    useAlert(t('FUNNEL.API.BOARD_CREATED'));
    await selectBoard(board.id);
  } catch (error) {
    useAlert(error.message);
  }
};

const onArchiveBoard = async () => {
  const boardId = activeBoard.value?.id;
  if (!boardId) return;

  try {
    await funnelStore.archiveBoard(boardId);
    archiveBoardDialogRef.value?.close();
    useAlert(t('FUNNEL.API.BOARD_ARCHIVED'));
    await selectBoard(boards.value[0]?.id ?? null);
  } catch (error) {
    useAlert(error.message);
  }
};

const onSubmitTask = async payload => {
  const { id, ...attributes } = payload;

  try {
    if (id) {
      await funnelStore.updateTask({ id, ...attributes });
      useAlert(t('FUNNEL.API.TASK_UPDATED'));
    } else {
      // lockVersion so existe em card ja gravado; enviar no create seria um campo a mais para
      // o strong params recusar.
      delete attributes.lockVersion;
      await funnelStore.createTask(attributes);
      useAlert(t('FUNNEL.API.TASK_CREATED'));
    }
    taskDialogRef.value?.close();
  } catch (error) {
    useAlert(error.message);
  }
};

const onRequestArchiveTask = task => {
  taskPendingArchive.value = task;
  taskDialogRef.value?.close();
  archiveTaskDialogRef.value?.open();
};

const onArchiveTask = async () => {
  const task = taskPendingArchive.value;
  if (!task) return;

  try {
    await funnelStore.archiveTask({ id: task.id });
    useAlert(t('FUNNEL.API.TASK_ARCHIVED'));
  } catch (error) {
    useAlert(error.message);
  } finally {
    taskPendingArchive.value = null;
    archiveTaskDialogRef.value?.close();
  }
};

const onMoveTask = async payload => {
  try {
    await funnelStore.moveTask(payload);
  } catch (error) {
    useAlert(error.message || t('FUNNEL.API.MOVE_ERROR'));
  }
};

const openTaskDialog = task => taskDialogRef.value?.open({ task });

const openNewTaskDialog = (step = null) =>
  taskDialogRef.value?.open({ step: step ?? steps.value[0] ?? null });

watch(
  () => route.params.accountId,
  () => {
    funnelStore.reset();
    if (isModuleEnabled.value) loadBoards();
  }
);

onMounted(() => {
  if (!isModuleEnabled.value) return;

  loadBoards();
  // Os multiselects do card escolhem entre agentes e etiquetas da conta; sem isso a primeira
  // abertura de um card mostraria as duas listas vazias.
  store.dispatch('agents/get');
  store.dispatch('labels/get');
});
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <div
      v-if="!isModuleEnabled"
      class="flex flex-col items-center justify-center h-full gap-2 px-6 text-center"
    >
      <h2 class="text-lg font-medium text-n-slate-12">
        {{ t('FUNNEL.DISABLED.TITLE') }}
      </h2>
      <p class="max-w-md text-sm text-n-slate-11">
        {{ t('FUNNEL.DISABLED.SUBTITLE') }}
      </p>
    </div>

    <template v-else>
      <header
        class="flex items-center justify-between gap-4 px-6 h-20 shrink-0"
      >
        <div class="relative flex items-center gap-2">
          <h1 class="text-xl font-medium truncate text-n-slate-12">
            {{ activeBoard?.name || t('FUNNEL.HEADER') }}
          </h1>
          <OnClickOutside
            v-if="boards.length"
            @trigger="showBoardSwitcher = false"
          >
            <Button
              icon="i-lucide-chevron-down"
              :variant="showBoardSwitcher ? 'faded' : 'ghost'"
              color="slate"
              size="xs"
              :aria-label="t('FUNNEL.BOARD.SWITCH')"
              @click="toggleBoardSwitcher"
            />
            <DropdownMenu
              v-if="showBoardSwitcher"
              :menu-items="boardMenuItems"
              class="ltr:left-0 rtl:right-0 top-9"
              @action="onBoardMenuAction"
            />
          </OnClickOutside>
        </div>

        <div class="flex items-center gap-2">
          <Button
            v-if="isAdministrator"
            variant="faded"
            color="slate"
            size="sm"
            icon="i-lucide-plus"
            :label="t('FUNNEL.BOARD.NEW')"
            @click="boardCreateDialogRef?.open()"
          />
          <Button
            v-if="activeBoard && canManageBoard"
            variant="ghost"
            color="slate"
            size="sm"
            icon="i-lucide-archive"
            :aria-label="t('FUNNEL.BOARD.ARCHIVE')"
            @click="archiveBoardDialogRef?.open()"
          />
          <Button
            v-if="activeBoard && canCreateTask"
            color="blue"
            size="sm"
            icon="i-lucide-plus"
            :label="t('FUNNEL.COLUMN.ADD_CARD')"
            @click="openNewTaskDialog()"
          />
        </div>
      </header>

      <div
        v-if="isLoadingBoard"
        class="flex items-center justify-center gap-2 grow text-n-slate-11"
      >
        <Spinner />
        <span class="text-sm">{{ t('FUNNEL.LOADING') }}</span>
      </div>

      <div
        v-else-if="!boards.length"
        class="flex flex-col items-center justify-center gap-4 px-6 text-center grow"
      >
        <div class="flex flex-col gap-2">
          <h2 class="text-2xl font-medium text-n-slate-12">
            {{ t('FUNNEL.EMPTY_STATE.TITLE') }}
          </h2>
          <p class="max-w-md text-sm text-n-slate-11">
            {{ t('FUNNEL.EMPTY_STATE.SUBTITLE') }}
          </p>
        </div>
        <Button
          v-if="isAdministrator"
          color="blue"
          icon="i-lucide-plus"
          :label="t('FUNNEL.EMPTY_STATE.ACTION')"
          @click="boardCreateDialogRef?.open()"
        />
      </div>

      <FunnelBoardCanvas
        v-else
        :steps="steps"
        :tasks-by-step="tasksByStep"
        :can-edit="canCreateTask"
        class="grow min-h-0"
        @move="onMoveTask"
        @add-card="openNewTaskDialog"
        @open-task="openTaskDialog"
      />
    </template>

    <BoardCreateDialog
      ref="boardCreateDialogRef"
      :is-loading="uiFlags.creatingBoard"
      @create="onCreateBoard"
    />

    <TaskDialog
      ref="taskDialogRef"
      :steps="steps"
      :is-loading="isSavingTask"
      :can-archive="canManageBoard"
      :can-edit="canCreateTask"
      @submit="onSubmitTask"
      @archive="onRequestArchiveTask"
    />

    <Dialog
      ref="archiveBoardDialogRef"
      type="alert"
      :title="
        t('FUNNEL.BOARD.ARCHIVE_CONFIRM.TITLE', { name: activeBoard?.name })
      "
      :description="t('FUNNEL.BOARD.ARCHIVE_CONFIRM.DESCRIPTION')"
      :confirm-button-label="t('FUNNEL.BOARD.ARCHIVE_CONFIRM.CONFIRM')"
      :cancel-button-label="t('FUNNEL.BOARD.ARCHIVE_CONFIRM.CANCEL')"
      :is-loading="uiFlags.updatingBoard"
      @confirm="onArchiveBoard"
    />

    <Dialog
      ref="archiveTaskDialogRef"
      type="alert"
      :title="t('FUNNEL.TASK.ARCHIVE_CONFIRM.TITLE')"
      :description="t('FUNNEL.TASK.ARCHIVE_CONFIRM.DESCRIPTION')"
      :confirm-button-label="t('FUNNEL.TASK.ARCHIVE_CONFIRM.CONFIRM')"
      :cancel-button-label="t('FUNNEL.TASK.ARCHIVE_CONFIRM.CANCEL')"
      :is-loading="uiFlags.updatingTask"
      @confirm="onArchiveTask"
      @close="taskPendingArchive = null"
    />
  </section>
</template>
