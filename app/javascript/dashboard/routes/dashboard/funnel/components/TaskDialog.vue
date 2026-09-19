<script setup>
import { computed, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import TaskActivity from './TaskActivity.vue';
import TaskAssociations from './TaskAssociations.vue';
import { formatMoney, TASK_PRIORITIES } from 'dashboard/helper/funnelHelper';
import { useFunnelStore } from 'dashboard/stores/funnel';

const props = defineProps({
  steps: { type: Array, default: () => [] },
  isLoading: { type: Boolean, default: false },
  canArchive: { type: Boolean, default: false },
  canEdit: { type: Boolean, default: false },
});

const emit = defineEmits(['submit', 'archive']);

const { t } = useI18n();
const funnelStore = useFunnelStore();

const dialogRef = ref(null);
const editingTask = ref(null);

const form = reactive({
  title: '',
  description: '',
  funnelStepId: '',
  priority: '',
  dueAt: '',
  value: '',
});

// Atributos personalizados viram lista de pares para poder editar: um objeto nao tem ordem, e
// renomear uma chave num objeto reativo significaria apagar e recriar a entrada a cada tecla.
const attributePairs = ref([]);

const isEditing = computed(() => Boolean(editingTask.value));

// As associacoes gravam na hora e devolvem o card inteiro. Ler da store e nao de editingTask
// faz o painel refletir a gravacao sem o dialogo precisar reabrir.
const liveTask = computed(() =>
  editingTask.value ? funnelStore.getTask(editingTask.value.id) : null
);
const isInvalid = computed(() => !form.title.trim());

// O erro do titulo so aparece depois que o usuario saiu do campo ou tentou gravar. Antes disso o
// dialogo abria ja repreendendo por um campo em que ninguem tinha tocado.
const titleTouched = ref(false);
const showTitleError = computed(() => titleTouched.value && isInvalid.value);

const boardCurrency = computed(
  () => funnelStore.getActiveBoard?.currency || 'BRL'
);

// Confirma a ordem de grandeza enquanto se digita: "1250" vira "R$ 1.250" embaixo do campo, entao
// um zero a mais aparece antes de virar oportunidade de dez mil no relatorio.
const valuePreview = computed(() => {
  if (form.value === '') return '';

  const amount = Number(form.value);
  return Number.isFinite(amount)
    ? formatMoney(amount, boardCurrency.value)
    : '';
});

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

// O valor chega da API como texto ("1250.5") para nao passar por float. <input type="number">
// recusa null e undefined, entao o vazio precisa virar string vazia antes de chegar nele.
const toNumberInput = value => {
  if (value === null || value === undefined || value === '') return '';

  const number = Number(value);
  return Number.isFinite(number) ? String(number) : '';
};

const resetForm = () => {
  funnelStore.clearTaskEvents();
  editingTask.value = null;
  titleTouched.value = false;
  form.title = '';
  form.description = '';
  form.funnelStepId = props.steps[0]?.id ?? '';
  form.priority = '';
  form.dueAt = '';
  form.value = '';
  attributePairs.value = [];
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
    form.value = toNumberInput(task.value);
    attributePairs.value = Object.entries(task.customAttributes ?? {}).map(
      ([key, value]) => ({ key, value: String(value ?? '') })
    );
  } else if (step) {
    form.funnelStepId = step.id;
  }

  dialogRef.value?.open();
};

const close = () => dialogRef.value?.close();

const handleConfirm = () => {
  titleTouched.value = true;
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
    value: form.value === '' ? null : Number(form.value),
    // Par sem chave e linha que o usuario comecou e nao terminou; mandar "" como chave criaria
    // um atributo invisivel no card.
    customAttributes: Object.fromEntries(
      attributePairs.value
        .filter(pair => pair.key.trim())
        .map(pair => [pair.key.trim(), pair.value])
    ),
  });
};

defineExpose({ open, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="3xl"
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
    <div class="grid grid-cols-1 gap-6 md:grid-cols-2">
      <div class="flex flex-col gap-4">
        <Input
          v-model="form.title"
          :label="t('FUNNEL.TASK.TITLE_LABEL')"
          :placeholder="t('FUNNEL.TASK.TITLE_PLACEHOLDER')"
          :message="showTitleError ? t('FUNNEL.TASK.TITLE_REQUIRED') : ''"
          :message-type="showTitleError ? 'error' : 'info'"
          :disabled="isLoading"
          autofocus
          @blur="titleTouched = true"
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
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <Input
            v-model="form.dueAt"
            type="datetime-local"
            :label="t('FUNNEL.TASK.DUE_AT_LABEL')"
            :disabled="isLoading"
          />
          <!-- Sem este campo o quadro guardava moeda, a etapa guardava probabilidade e o
               relatorio somava funil ponderado, tudo sobre um valor que nao tinha por onde
               entrar. A pre-visualizacao embaixo confirma a ordem de grandeza do que foi
               digitado. -->
          <Input
            v-model="form.value"
            type="number"
            min="0"
            :label="t('FUNNEL.TASK.VALUE_LABEL')"
            :placeholder="t('FUNNEL.TASK.VALUE_PLACEHOLDER')"
            :message="valuePreview"
            :disabled="isLoading"
          />
        </div>
      </div>

      <section class="flex flex-col gap-2">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('FUNNEL.TASK.ATTRIBUTES') }}
        </span>
        <div
          v-for="(pair, index) in attributePairs"
          :key="index"
          class="flex items-end gap-2"
        >
          <Input
            v-model="pair.key"
            class="flex-1"
            :placeholder="t('FUNNEL.TASK.ATTRIBUTE_KEY')"
            :disabled="isLoading"
          />
          <Input
            v-model="pair.value"
            class="flex-1"
            :placeholder="t('FUNNEL.TASK.ATTRIBUTE_VALUE')"
            :disabled="isLoading"
          />
          <Button
            variant="ghost"
            color="ruby"
            size="sm"
            icon="i-lucide-x"
            type="button"
            :aria-label="t('FUNNEL.TASK.ATTRIBUTE_REMOVE')"
            :disabled="isLoading"
            @click="attributePairs.splice(index, 1)"
          />
        </div>
        <Button
          variant="link"
          color="slate"
          size="xs"
          icon="i-lucide-plus"
          type="button"
          :label="t('FUNNEL.TASK.ATTRIBUTE_ADD')"
          :disabled="isLoading"
          @click="attributePairs.push({ key: '', value: '' })"
        />
      </section>

      <!-- Associacoes so existem para card ja gravado: sem id nao ha onde pendurar responsavel
           nem conversa. No card novo a coluna explica isso em vez de ficar vazia. -->
      <div v-if="isEditing && liveTask" class="flex flex-col gap-5">
        <TaskAssociations :task="liveTask" :can-edit="canEdit" />
        <TaskActivity :task-id="liveTask.id" />
      </div>
      <p v-else class="text-xs text-n-slate-10">
        {{ t('FUNNEL.ASSOCIATIONS.AFTER_CREATE') }}
      </p>
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
