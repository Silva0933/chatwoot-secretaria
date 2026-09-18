<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useFunnelStore } from 'dashboard/stores/funnel';
import { frontendURL } from 'dashboard/helper/URLHelper';

import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  conversationId: { type: [Number, String], required: true },
});

const { t } = useI18n();
const { accountId, currentAccount } = useAccount();
const funnelStore = useFunnelStore();

const selectedBoardId = ref(null);

const isModuleEnabled = computed(() =>
  Boolean(currentAccount.value?.settings?.funnel_kanban_enabled)
);

const tasks = computed(() => funnelStore.conversationTasks);
const boards = computed(() => funnelStore.getBoards);
const uiFlags = computed(() => funnelStore.getUIFlags);
const isBusy = computed(
  () => uiFlags.value.fetchingConversationTasks || uiFlags.value.creatingTask
);

// Quadros onde este usuario pode abrir card e que ainda nao tem um para esta conversa: a regra
// proibe dois cards ativos da mesma conversa no mesmo quadro, entao oferecer um ja usado so
// levaria a um erro previsivel.
const availableBoards = computed(() => {
  const used = new Set(tasks.value.map(task => task.funnelBoardId));
  return boards.value.filter(
    board => board.permissions?.createTask && !used.has(board.id)
  );
});

const boardOptions = computed(() =>
  availableBoards.value.map(board => ({ value: board.id, label: board.name }))
);

const stepOptionsFor = task => {
  const board = boards.value.find(item => item.id === task.funnelBoardId);
  return (board?.steps ?? []).map(step => ({
    value: step.id,
    label: step.name,
  }));
};

const boardLink = task =>
  frontendURL(`accounts/${accountId.value}/funnel?board=${task.funnelBoardId}`);

const load = async () => {
  if (!isModuleEnabled.value) return;

  try {
    if (!boards.value.length) await funnelStore.fetchBoards();
    await funnelStore.fetchConversationTasks(props.conversationId);
  } catch (error) {
    useAlert(error.message);
  }
};

// Trocar a etapa sem sair da conversa e o comportamento que o relatorio destaca: o atendente
// acabou de combinar a consulta, e voltar ao quadro para arrastar o card quebra o atendimento.
const onChangeStep = async (task, stepId) => {
  if (!stepId || stepId === task.funnelStepId) return;

  try {
    await funnelStore.moveConversationTask({
      id: task.id,
      boardId: task.funnelBoardId,
      stepId,
      conversationId: props.conversationId,
    });
    useAlert(t('FUNNEL.CONVERSATION.STEP_CHANGED'));
  } catch (error) {
    useAlert(error.message);
  }
};

const onCreate = async () => {
  const boardId = selectedBoardId.value ?? availableBoards.value[0]?.id;
  if (!boardId) return;

  try {
    await funnelStore.createTaskFromConversation({
      conversationId: props.conversationId,
      boardId,
    });
    selectedBoardId.value = null;
    useAlert(t('FUNNEL.API.TASK_CREATED'));
  } catch (error) {
    useAlert(error.message);
  }
};

watch(() => props.conversationId, load, { immediate: true });
</script>

<template>
  <div v-if="isModuleEnabled" class="flex flex-col gap-3">
    <div v-if="isBusy && !tasks.length" class="flex justify-center py-3">
      <Spinner />
    </div>

    <div
      v-for="task in tasks"
      :key="task.id"
      class="flex flex-col gap-2 p-3 border rounded-lg border-n-weak bg-n-solid-1"
    >
      <div class="flex items-start justify-between gap-2">
        <span class="text-sm font-medium break-words text-n-slate-12">
          {{ task.title }}
        </span>
        <router-link
          :to="boardLink(task)"
          class="shrink-0 text-n-slate-11 hover:text-n-slate-12"
          :aria-label="t('FUNNEL.CONVERSATION.OPEN_BOARD')"
          :title="t('FUNNEL.CONVERSATION.OPEN_BOARD')"
        >
          <Icon icon="i-lucide-external-link" class="size-4" />
        </router-link>
      </div>

      <span class="flex items-center gap-1.5 text-xs text-n-slate-11">
        <Icon icon="i-lucide-filter" class="size-3" />
        {{ task.boardName }}
      </span>

      <label class="flex flex-col gap-1">
        <span class="text-xs font-medium text-n-slate-11">
          {{ t('FUNNEL.TASK.STEP_LABEL') }}
        </span>
        <Select
          :model-value="task.funnelStepId"
          :options="stepOptionsFor(task)"
          :disabled="isBusy"
          :aria-label="t('FUNNEL.TASK.STEP_LABEL')"
          @update:model-value="value => onChangeStep(task, value)"
        />
      </label>
    </div>

    <div v-if="!tasks.length && !isBusy" class="flex flex-col gap-2">
      <p class="text-xs text-n-slate-10">
        {{ t('FUNNEL.CONVERSATION.EMPTY') }}
      </p>
    </div>

    <!-- Um card por quadro: a conversa pode viver no funil comercial e no de pos-atendimento
         ao mesmo tempo, entao a opcao de criar continua enquanto sobrar quadro livre. -->
    <div v-if="availableBoards.length" class="flex flex-col gap-2">
      <Select
        v-if="availableBoards.length > 1"
        v-model="selectedBoardId"
        :options="boardOptions"
        :placeholder="t('FUNNEL.CONVERSATION.PICK_BOARD')"
        :disabled="isBusy"
        :aria-label="t('FUNNEL.CONVERSATION.PICK_BOARD')"
      />
      <Button
        variant="faded"
        color="slate"
        size="sm"
        icon="i-lucide-plus"
        :label="t('FUNNEL.CONVERSATION.CREATE')"
        :disabled="isBusy"
        :is-loading="uiFlags.creatingTask"
        @click="onCreate"
      />
    </div>
  </div>
</template>
