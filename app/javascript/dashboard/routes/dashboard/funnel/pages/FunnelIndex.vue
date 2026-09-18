<script setup>
import { computed, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { OnClickOutside } from '@vueuse/components';

import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useFunnelStore } from 'dashboard/stores/funnel';
import { EMPTY_FILTERS, formatMoney } from 'dashboard/helper/funnelHelper';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';

import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import BoardCreateDialog from '../components/BoardCreateDialog.vue';
import BoardSettingsDialog from '../components/BoardSettingsDialog.vue';
import FunnelBoardCanvas from '../components/FunnelBoardCanvas.vue';
import FunnelToolbar from '../components/FunnelToolbar.vue';
import StepDialog from '../components/StepDialog.vue';
import TaskDialog from '../components/TaskDialog.vue';

const { t, locale } = useI18n();
const route = useRoute();
const router = useRouter();
const funnelStore = useFunnelStore();
const store = useStore();
const { currentAccount, accountId } = useAccount();

const currentRole = useMapGetter('getCurrentRole');

const boardCreateDialogRef = ref(null);
const taskDialogRef = ref(null);
const stepDialogRef = ref(null);
const boardSettingsRef = ref(null);
const stepPendingDelete = ref(null);
const deleteStepDialogRef = ref(null);
const deleteTargetStepId = ref(null);
const archiveBoardDialogRef = ref(null);
const archiveTaskDialogRef = ref(null);
const showBoardSwitcher = ref(false);
const taskPendingArchive = ref(null);

// Erro de carga precisa de estado proprio. Sem ele, uma falha de rede caia no mesmo "Nenhum
// quadro por aqui" do quadro vazio — a tela afirmava que nao havia quadros quando na verdade
// nao tinha conseguido perguntar.
const loadError = ref(null);

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
const canManageSettings = computed(
  () => activeBoard.value?.permissions?.manageSettings ?? false
);

// O contador do cabecalho soma o quadro inteiro, nao a coluna: e a leitura de volume que a
// referencia mostra ao lado do nome do funil.
const totalTasks = computed(() => funnelStore.tasks.length);
const visibleTaskCount = computed(() => funnelStore.getFilteredTasks.length);

// O total ponderado so aparece quando ha valor lancado: um "R$ 0" permanente num funil de
// clinica, onde ninguem preenche valor, seria ruido fixo no cabecalho.
const pipelineValue = computed(() => funnelStore.getPipelineValue);
const showPipelineValue = computed(() => pipelineValue.value > 0);
const pipelineValueLabel = computed(() =>
  formatMoney(
    pipelineValue.value,
    activeBoard.value?.currency ?? 'BRL',
    locale.value.replace('_', '-')
  )
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

// Os filtros vivem na URL para que um quadro filtrado seja um link que se manda para o colega,
// e para o botao voltar do navegador desfazer um filtro em vez de sair da tela (PRD 4.9).
const FILTER_QUERY_KEYS = {
  search: 'q',
  assigneeId: 'agent',
  inboxId: 'inbox',
  priority: 'priority',
  labelId: 'label',
};

const readFiltersFromUrl = () => {
  const filters = {};
  Object.entries(FILTER_QUERY_KEYS).forEach(([key, param]) => {
    const raw = route.query[param];
    if (raw === undefined) return;
    filters[key] =
      key === 'search' || key === 'priority' ? String(raw) : Number(raw);
  });

  funnelStore.setFilters({ ...EMPTY_FILTERS, ...filters });
  if (route.query.sort) funnelStore.setSortBy(String(route.query.sort));
};

const writeFiltersToUrl = () => {
  const query = { ...route.query };

  Object.entries(FILTER_QUERY_KEYS).forEach(([key, param]) => {
    const value = funnelStore.filters[key];
    if (value === EMPTY_FILTERS[key]) delete query[param];
    else query[param] = String(value);
  });

  if (funnelStore.sortBy === 'position') delete query.sort;
  else query.sort = funnelStore.sortBy;

  const changed = Object.keys({ ...query, ...route.query }).some(
    key => String(query[key] ?? '') !== String(route.query[key] ?? '')
  );
  if (changed)
    router.replace({ name: route.name, params: route.params, query });
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
  loadError.value = null;
  try {
    await funnelStore.fetchBoards();
  } catch (error) {
    // 401 aqui e recusa da policy e nao sessao expirada: o RequestExceptionHandler do Chatwoot
    // responde 401 para Pundit. Dizer "sem permissao" e mais util que "erro ao carregar".
    const denied = /not authorized/i.test(error.message ?? '');
    loadError.value = denied ? 'forbidden' : 'error';
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

// Quantos cards a etapa que vai sair carrega: e o que decide se o dialogo pede um destino.
const stepTaskCount = computed(
  () => (tasksByStep.value[stepPendingDelete.value?.id] ?? []).length
);

const deleteTargetOptions = computed(() =>
  steps.value
    .filter(step => step.id !== stepPendingDelete.value?.id)
    .map(step => ({ value: step.id, label: step.name }))
);

const onReorderSteps = async stepIds => {
  try {
    await funnelStore.reorderSteps({ stepIds });
  } catch (error) {
    useAlert(error.message);
  }
};

const onSubmitStep = async payload => {
  try {
    await funnelStore.saveStep(payload);
    stepDialogRef.value?.close();
    useAlert(payload.id ? t('FUNNEL.STEP.SAVED') : t('FUNNEL.STEP.CREATED'));
  } catch (error) {
    useAlert(error.message);
  }
};

const onRequestDeleteStep = step => {
  stepPendingDelete.value = step;
  // Sugere a primeira etapa que sobra como destino, para o caso comum de nao haver escolha real.
  deleteTargetStepId.value =
    steps.value.find(item => item.id !== step.id)?.id ?? null;
  stepDialogRef.value?.close();
  deleteStepDialogRef.value?.open();
};

const onDeleteStep = async () => {
  const step = stepPendingDelete.value;
  if (!step) return;

  try {
    await funnelStore.deleteStep({
      id: step.id,
      targetStepId: deleteTargetStepId.value,
    });
    useAlert(t('FUNNEL.STEP.DELETED'));
  } catch (error) {
    useAlert(error.message);
  } finally {
    stepPendingDelete.value = null;
    deleteStepDialogRef.value?.close();
  }
};

const openReport = () =>
  router.push({
    name: 'funnel_report',
    params: route.params,
    query: { board: String(activeBoard.value.id) },
  });

const openTaskDialog = task => taskDialogRef.value?.open({ task });

// Abre a conversa na caixa de entrada dela, como TaskAssociations ja faz: e la que estao o
// editor e o historico, e nao numa aba do card.
const goToConversation = conversation =>
  router.push(
    frontendURL(
      conversationUrl({
        accountId: accountId.value,
        activeInbox: conversation.inboxId,
        id: conversation.id,
      })
    )
  );

const openNewTaskDialog = (step = null) =>
  taskDialogRef.value?.open({ step: step ?? steps.value[0] ?? null });

const loadEverything = () => {
  if (!isModuleEnabled.value) return;

  loadBoards();
  // Os multiselects do card escolhem entre agentes e etiquetas da conta; sem isso a primeira
  // abertura de um card mostraria as duas listas vazias.
  store.dispatch('agents/get');
  store.dispatch('labels/get');
  // O filtro por caixa precisa da lista de inboxes da conta.
  store.dispatch('inboxes/get');
};

// Watch e nao onMounted: currentAccount chega de forma assincrona, e num carregamento direto
// da URL o componente monta antes dela estar na store. Um onMounted leria isModuleEnabled como
// falso, desistiria para sempre, e o quadro apareceria vazio sem nenhuma requisicao ter saido.
// O mesmo watch cobre a troca de conta, onde a lista precisa ser recarregada mesmo com o
// modulo ligado nas duas.
watch(() => [funnelStore.filters, funnelStore.sortBy], writeFiltersToUrl, {
  deep: true,
});

watch(
  [isModuleEnabled, () => route.params.accountId],
  ([, accountId], previous) => {
    if (previous && previous[1] !== accountId) funnelStore.reset();
    if (isModuleEnabled.value) readFiltersFromUrl();
    loadEverything();
  },
  { immediate: true }
);
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
          <span
            v-if="activeBoard"
            class="px-2 py-0.5 text-xs font-medium rounded-full bg-n-alpha-2 text-n-slate-11"
            :title="t('FUNNEL.BOARD.TOTAL')"
          >
            {{ totalTasks }}
          </span>
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
          <span
            v-if="showPipelineValue"
            class="px-2 py-1 text-xs font-medium rounded-md bg-n-alpha-2 text-n-slate-11"
            :title="t('FUNNEL.SETTINGS.PIPELINE_VALUE')"
          >
            {{ pipelineValueLabel }}
          </span>
          <Button
            v-if="activeBoard"
            variant="ghost"
            color="slate"
            size="sm"
            icon="i-lucide-chart-no-axes-column"
            :aria-label="t('FUNNEL.REPORT.TITLE')"
            @click="openReport"
          />
          <Button
            v-if="activeBoard && canManageSettings"
            variant="ghost"
            color="slate"
            size="sm"
            icon="i-lucide-settings"
            :aria-label="t('FUNNEL.SETTINGS.CONFIGURE')"
            @click="boardSettingsRef?.open()"
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
        v-else-if="loadError"
        class="flex flex-col items-center justify-center gap-3 px-6 text-center grow"
      >
        <Icon
          :icon="
            loadError === 'forbidden' ? 'i-lucide-lock' : 'i-lucide-cloud-off'
          "
          class="size-8 text-n-slate-10"
        />
        <div class="flex flex-col gap-1">
          <h2 class="text-lg font-medium text-n-slate-12">
            {{
              loadError === 'forbidden'
                ? t('FUNNEL.STATES.FORBIDDEN_TITLE')
                : t('FUNNEL.STATES.ERROR_TITLE')
            }}
          </h2>
          <p class="max-w-md text-sm text-n-slate-11">
            {{
              loadError === 'forbidden'
                ? t('FUNNEL.STATES.FORBIDDEN_SUBTITLE')
                : t('FUNNEL.STATES.ERROR_SUBTITLE')
            }}
          </p>
        </div>
        <Button
          v-if="loadError !== 'forbidden'"
          variant="faded"
          color="slate"
          size="sm"
          icon="i-lucide-refresh-cw"
          :label="t('FUNNEL.STATES.RETRY')"
          @click="loadBoards"
        />
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

      <FunnelToolbar v-if="activeBoard" />

      <div
        v-if="activeBoard && funnelStore.hasFilters && !visibleTaskCount"
        class="flex flex-col items-center justify-center gap-2 px-6 text-center grow"
      >
        <h2 class="text-lg font-medium text-n-slate-12">
          {{ t('FUNNEL.FILTERS.EMPTY_TITLE') }}
        </h2>
        <p class="max-w-md text-sm text-n-slate-11">
          {{ t('FUNNEL.FILTERS.EMPTY_SUBTITLE') }}
        </p>
      </div>

      <FunnelBoardCanvas
        v-else
        :steps="steps"
        :tasks-by-step="tasksByStep"
        :can-edit="canCreateTask"
        :can-manage-steps="canManageSettings"
        :can-reorder="funnelStore.canReorder"
        class="grow min-h-0"
        @move="onMoveTask"
        @add-card="openNewTaskDialog"
        @open-task="openTaskDialog"
        @open-conversation="goToConversation"
        @configure-step="stepDialogRef?.open($event)"
        @reorder-steps="onReorderSteps"
        @add-step="stepDialogRef?.open()"
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

    <!-- O dialogo grava sozinho: as tres chamadas precisam ser em sequencia, e um emit nao da
         para aguardar. -->
    <BoardSettingsDialog ref="boardSettingsRef" :board="activeBoard" />

    <StepDialog
      ref="stepDialogRef"
      :steps="steps"
      :is-loading="uiFlags.savingStep"
      @submit="onSubmitStep"
      @destroy="onRequestDeleteStep"
    />

    <Dialog
      ref="deleteStepDialogRef"
      type="alert"
      :title="
        t('FUNNEL.STEP.DELETE_CONFIRM_TITLE', { name: stepPendingDelete?.name })
      "
      :confirm-button-label="t('FUNNEL.STEP.DELETE_CONFIRM')"
      :cancel-button-label="t('FUNNEL.STEP.CANCEL')"
      :is-loading="uiFlags.savingStep"
      @confirm="onDeleteStep"
    >
      <div class="flex flex-col gap-3">
        <p class="text-sm text-n-slate-11">
          {{
            stepTaskCount
              ? t('FUNNEL.STEP.DELETE_CONFIRM_MOVE', { count: stepTaskCount })
              : t('FUNNEL.STEP.DELETE_CONFIRM_EMPTY')
          }}
        </p>
        <label v-if="stepTaskCount" class="flex flex-col gap-1">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('FUNNEL.STEP.DELETE_TARGET_LABEL') }}
          </span>
          <Select
            v-model="deleteTargetStepId"
            :options="deleteTargetOptions"
            :aria-label="t('FUNNEL.STEP.DELETE_TARGET_LABEL')"
          />
        </label>
      </div>
    </Dialog>

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
