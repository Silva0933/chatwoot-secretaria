<script setup>
import { ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { neighboursAt } from 'dashboard/helper/funnelHelper';

import Draggable from 'vuedraggable';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import FunnelColumn from './FunnelColumn.vue';

const props = defineProps({
  steps: { type: Array, default: () => [] },
  tasksByStep: { type: Object, default: () => ({}) },
  canEdit: { type: Boolean, default: false },
  canManageSteps: { type: Boolean, default: false },
  canReorder: { type: Boolean, default: true },
});

const emit = defineEmits([
  'move',
  'addCard',
  'openTask',
  'configureStep',
  'addStep',
]);

const { t } = useI18n();
const addStepLabel = t('FUNNEL.STEP.NEW');

// O quadro trabalha sobre uma copia das colunas. O vuedraggable precisa mutar o array para
// mostrar o card na posicao nova durante o arrasto, e mutar o getter da store faria a coluna
// pular de volta ao valor calculado antes de a API responder.
const columns = ref({});
// Copia local tambem para as etapas: o vuedraggable precisa mutar o array durante o arrasto.
const localSteps = ref([]);

const syncColumns = () => {
  columns.value = Object.fromEntries(
    props.steps.map(step => [step.id, [...(props.tasksByStep[step.id] ?? [])]])
  );
  localSteps.value = [...props.steps];
};

watch(() => [props.steps, props.tasksByStep], syncColumns, {
  immediate: true,
});

// A ordem final das colunas, como o arrasto deixou. Poucas etapas, entao reescrever todos os
// ranks e barato; nos cards seria caro, e por isso la o rank e fracionario.
const onStepDragEnd = () =>
  emit(
    'reorderSteps',
    localSteps.value.map(step => step.id)
  );

const onColumnChange = ({ stepId, event }) => {
  // `removed` chega na coluna de origem depois de `added` na de destino: tratar os dois
  // mandaria duas requisicoes para o mesmo arrasto.
  const change = event.added || event.moved;
  if (!change) return;

  const { afterId, beforeId } = neighboursAt(
    columns.value[stepId],
    change.element.id
  );

  emit('move', { id: change.element.id, stepId, afterId, beforeId });
};
</script>

<template>
  <div class="flex h-full gap-3 px-6 pb-4 overflow-x-auto">
    <Draggable
      v-model="localSteps"
      :disabled="!canManageSteps"
      item-key="id"
      tag="div"
      class="flex h-full gap-3"
      handle=".funnel-step-handle"
      ghost-class="opacity-40"
      animation="150"
      @end="onStepDragEnd"
    >
      <template #item="{ element }">
        <FunnelColumn
          :step="element"
          :tasks="columns[element.id] ?? []"
          :can-edit="canEdit"
          :can-drag="canEdit && canReorder"
          :can-manage-steps="canManageSteps"
          @change="onColumnChange"
          @add-card="$emit('addCard', $event)"
          @open-task="$emit('openTask', $event)"
          @configure="$emit('configureStep', $event)"
        />
      </template>
    </Draggable>

    <button
      v-if="canManageSteps"
      type="button"
      class="flex items-center justify-center gap-2 w-14 shrink-0 text-sm rounded-xl border border-dashed border-n-weak text-n-slate-11 hover:text-n-slate-12 hover:border-n-slate-6"
      :aria-label="addStepLabel"
      :title="addStepLabel"
      @click="$emit('addStep')"
    >
      <Icon icon="i-lucide-plus" class="size-4" />
    </button>
  </div>
</template>
