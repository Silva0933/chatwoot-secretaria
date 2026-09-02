<script setup>
import { computed, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import { TASK_PRIORITIES } from 'dashboard/helper/funnelHelper';

const props = defineProps({
  steps: { type: Array, default: () => [] },
  isLoading: { type: Boolean, default: false },
  canArchive: { type: Boolean, default: false },
});

const emit = defineEmits(['submit', 'archive']);

const { t } = useI18n();

const dialogRef = ref(null);
const editingTask = ref(null);

const form = reactive({
  title: '',
  description: '',
  funnelStepId: '',
  priority: '',
  dueAt: '',
});

const isEditing = computed(() => Boolean(editingTask.value));
const isInvalid = computed(() => !form.title.trim());

const stepOptions = computed(() =>
  props.steps.map(step => ({ value: step.id, label: step.name }))
);

const priorityOptions = computed(() => [
  { value: '', label: t('FUNNEL.PRIORITY.NONE') },
  ...TASK_PRIORITIES.map(priority => ({
    value: priority,
    label: t(`FUNNEL.PRIORITY.${priority.toUpperCase()}`),
  })),
]);

// <input type="datetime-local"> so aceita horario local sem fuso; o ISO da API tem os dois.
const toLocalInput = value => {
  if (!value) return '';

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '';

  const pad = number => String(number).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
};

const fromLocalInput = value => {
  if (!value) return null;

  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
};

const resetForm = () => {
  editingTask.value = null;
  form.title = '';
  form.description = '';
  form.funnelStepId = props.steps[0]?.id ?? '';
  form.priority = '';
  form.dueAt = '';
};

const open = ({ task = null, step = null } = {}) => {
  resetForm();
  editingTask.value = task;

  if (task) {
    form.title = task.title ?? '';
    form.description = task.description ?? '';
    form.funnelStepId = task.funnelStepId ?? props.steps[0]?.id ?? '';
    form.priority = task.priority ?? '';
    form.dueAt = toLocalInput(task.dueAt);
  } else if (step) {
    form.funnelStepId = step.id;
  }

  dialogRef.value?.open();
};

const close = () => dialogRef.value?.close();

const handleConfirm = () => {
  if (isInvalid.value) return;

  emit('submit', {
    id: editingTask.value?.id ?? null,
    // lock_version acompanha a edicao para que o backend recuse uma gravacao sobre uma
    // versao que outro agente ja alterou, em vez de sobrescrever em silencio.
    lockVersion: editingTask.value?.lockVersion,
    title: form.title.trim(),
    description: form.description.trim() || null,
    funnelStepId: form.funnelStepId || null,
    priority: form.priority || null,
    dueAt: fromLocalInput(form.dueAt),
  });
};

defineExpose({ open, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="lg"
    :title="
      isEditing ? t('FUNNEL.TASK.EDIT_TITLE') : t('FUNNEL.TASK.CREATE_TITLE')
    "
    :confirm-button-label="
      isEditing ? t('FUNNEL.TASK.SAVE') : t('FUNNEL.TASK.CREATE')
    "
    :cancel-button-label="t('FUNNEL.TASK.CANCEL')"
    :disable-confirm-button="isInvalid"
    :is-loading="isLoading"
    @confirm="handleConfirm"
    @close="resetForm"
  >
    <div class="flex flex-col gap-4">
      <Input
        v-model="form.title"
        :label="t('FUNNEL.TASK.TITLE_LABEL')"
        :placeholder="t('FUNNEL.TASK.TITLE_PLACEHOLDER')"
        :message="isInvalid ? t('FUNNEL.TASK.TITLE_REQUIRED') : ''"
        :message-type="isInvalid ? 'error' : 'info'"
        :disabled="isLoading"
        autofocus
      />
      <TextArea
        v-model="form.description"
        :label="t('FUNNEL.TASK.DESCRIPTION_LABEL')"
        :placeholder="t('FUNNEL.TASK.DESCRIPTION_PLACEHOLDER')"
        :disabled="isLoading"
        :max-length="1000"
        auto-height
      />
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <label class="flex flex-col gap-1">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('FUNNEL.TASK.STEP_LABEL') }}
          </span>
          <Select
            v-model="form.funnelStepId"
            :options="stepOptions"
            :disabled="isLoading"
            :aria-label="t('FUNNEL.TASK.STEP_LABEL')"
          />
        </label>
        <label class="flex flex-col gap-1">
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('FUNNEL.PRIORITY.LABEL') }}
          </span>
          <Select
            v-model="form.priority"
            :options="priorityOptions"
            :disabled="isLoading"
            :aria-label="t('FUNNEL.PRIORITY.LABEL')"
          />
        </label>
      </div>
      <Input
        v-model="form.dueAt"
        type="datetime-local"
        :label="t('FUNNEL.TASK.DUE_AT_LABEL')"
        :disabled="isLoading"
      />
    </div>

    <template #footer>
      <div class="flex items-center justify-between w-full gap-3">
        <Button
          v-if="isEditing && canArchive"
          variant="ghost"
          color="ruby"
          size="sm"
          icon="i-lucide-archive"
          :label="t('FUNNEL.TASK.ARCHIVE')"
          type="button"
          :disabled="isLoading"
          @click="emit('archive', editingTask)"
        />
        <span v-else />
        <div class="flex items-center gap-2">
          <Button
            variant="faded"
            color="slate"
            :label="t('FUNNEL.TASK.CANCEL')"
            type="button"
            @click="close"
          />
          <Button
            color="blue"
            :label="isEditing ? t('FUNNEL.TASK.SAVE') : t('FUNNEL.TASK.CREATE')"
            type="submit"
            :disabled="isInvalid || isLoading"
            :is-loading="isLoading"
          />
        </div>
      </div>
    </template>
  </Dialog>
</template>
