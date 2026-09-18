<script setup>
import { computed, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import { STAGE_TYPES } from 'dashboard/helper/funnelHelper';

const props = defineProps({
  steps: { type: Array, default: () => [] },
  isLoading: { type: Boolean, default: false },
});

const emit = defineEmits(['submit', 'destroy']);

// Paleta fixa em vez de seletor livre: a cor pinta o cabecalho inteiro da coluna, e um roxo
// escolhido a dedo pelo usuario pode deixar o texto ilegivel ou destoar do resto do quadro.
const STEP_COLORS = [
  '#6b7280',
  '#3b82f6',
  '#8b5cf6',
  '#ec4899',
  '#ef4444',
  '#f59e0b',
  '#10b981',
  '#14b8a6',
];

const { t } = useI18n();

const dialogRef = ref(null);
const editingStep = ref(null);
const form = reactive({
  name: '',
  color: STEP_COLORS[0],
  stageType: 'open',
  probability: 0,
});

const isEditing = computed(() => Boolean(editingStep.value));
const isInvalid = computed(() => !form.name.trim());

const stageTypeOptions = computed(() =>
  STAGE_TYPES.map(type => ({
    value: type,
    label: t(`FUNNEL.STAGE_TYPE.${type.toUpperCase()}`),
  }))
);

// Excluir a ultima etapa deixaria o quadro sem nenhuma coluna onde pousar um card.
const canDelete = computed(() => isEditing.value && props.steps.length > 1);

const open = (step = null) => {
  editingStep.value = step;
  form.name = step?.name ?? '';
  form.color = step?.color ?? STEP_COLORS[0];
  form.stageType = step?.stageType ?? 'open';
  form.probability = step?.probability ?? 0;
  dialogRef.value?.open();
};

const close = () => dialogRef.value?.close();

const handleConfirm = () => {
  if (isInvalid.value) return;

  emit('submit', {
    id: editingStep.value?.id ?? null,
    name: form.name.trim(),
    color: form.color,
    stageType: form.stageType,
    probability: Number(form.probability) || 0,
  });
};

defineExpose({ open, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="md"
    :title="isEditing ? t('FUNNEL.STEP.EDIT') : t('FUNNEL.STEP.NEW')"
    :is-loading="isLoading"
    @confirm="handleConfirm"
  >
    <div class="flex flex-col gap-4">
      <Input
        v-model="form.name"
        :label="t('FUNNEL.STEP.NAME_LABEL')"
        :placeholder="t('FUNNEL.STEP.NAME_PLACEHOLDER')"
        :disabled="isLoading"
        autofocus
      />

      <div class="flex flex-col gap-2">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('FUNNEL.STEP.COLOR_LABEL') }}
        </span>
        <div class="flex flex-wrap gap-2">
          <button
            v-for="color in STEP_COLORS"
            :key="color"
            type="button"
            class="rounded-full size-7 ring-offset-2 ring-offset-n-solid-1"
            :class="form.color === color ? 'ring-2 ring-n-brand' : ''"
            :style="{ backgroundColor: color }"
            :aria-label="color"
            :aria-pressed="form.color === color"
            :disabled="isLoading"
            @click="form.color = color"
          />
        </div>
      </div>

      <label class="flex flex-col gap-1">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('FUNNEL.STEP.TYPE_LABEL') }}
        </span>
        <Select
          v-model="form.stageType"
          :options="stageTypeOptions"
          :disabled="isLoading"
          :aria-label="t('FUNNEL.STEP.TYPE_LABEL')"
        />
        <span class="text-xs text-n-slate-10">
          {{ t('FUNNEL.STEP.TYPE_HINT') }}
        </span>
      </label>

      <Input
        v-model="form.probability"
        type="number"
        min="0"
        max="100"
        :label="t('FUNNEL.STEP.PROBABILITY_LABEL')"
        :message="t('FUNNEL.STEP.PROBABILITY_HINT')"
        :disabled="isLoading"
      />
    </div>

    <template #footer>
      <div class="flex items-center justify-between w-full gap-3">
        <Button
          v-if="canDelete"
          variant="ghost"
          color="ruby"
          size="sm"
          icon="i-lucide-trash-2"
          :label="t('FUNNEL.STEP.DELETE')"
          type="button"
          :disabled="isLoading"
          @click="emit('destroy', editingStep)"
        />
        <span v-else />
        <div class="flex items-center gap-2">
          <Button
            variant="faded"
            color="slate"
            :label="t('FUNNEL.STEP.CANCEL')"
            type="button"
            @click="close"
          />
          <Button
            color="blue"
            :label="isEditing ? t('FUNNEL.STEP.SAVE') : t('FUNNEL.STEP.CREATE')"
            type="submit"
            :disabled="isInvalid || isLoading"
            :is-loading="isLoading"
          />
        </div>
      </div>
    </template>
  </Dialog>
</template>
