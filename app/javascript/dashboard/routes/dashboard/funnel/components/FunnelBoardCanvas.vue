<script setup>
import { ref, watch } from 'vue';
import { neighboursAt } from 'dashboard/helper/funnelHelper';

import FunnelColumn from './FunnelColumn.vue';

const props = defineProps({
  steps: { type: Array, default: () => [] },
  tasksByStep: { type: Object, default: () => ({}) },
  canEdit: { type: Boolean, default: false },
});

const emit = defineEmits(['move', 'addCard', 'openTask']);

// O quadro trabalha sobre uma copia das colunas. O vuedraggable precisa mutar o array para
// mostrar o card na posicao nova durante o arrasto, e mutar o getter da store faria a coluna
// pular de volta ao valor calculado antes de a API responder.
const columns = ref({});

const syncColumns = () => {
  columns.value = Object.fromEntries(
    props.steps.map(step => [step.id, [...(props.tasksByStep[step.id] ?? [])]])
  );
};

watch(() => [props.steps, props.tasksByStep], syncColumns, {
  immediate: true,
});

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
    <FunnelColumn
      v-for="step in steps"
      :key="step.id"
      :step="step"
      :tasks="columns[step.id] ?? []"
      :can-edit="canEdit"
      @change="onColumnChange"
      @add-card="$emit('addCard', $event)"
      @open-task="$emit('openTask', $event)"
    />
  </div>
</template>
