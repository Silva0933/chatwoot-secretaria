<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Draggable from 'vuedraggable';

import Button from 'dashboard/components-next/button/Button.vue';
import FunnelCard from './FunnelCard.vue';

const props = defineProps({
  step: { type: Object, required: true },
  tasks: { type: Array, default: () => [] },
  canEdit: { type: Boolean, default: false },
});

const emit = defineEmits(['change', 'addCard', 'openTask']);

const { t } = useI18n();

const stageLabel = computed(() =>
  t(`FUNNEL.STAGE_TYPE.${(props.step.stageType || 'open').toUpperCase()}`)
);

// O change do vuedraggable dispara depois de a lista ja ter sido mutada, entao o pai le a
// ordem final direto do array em vez de recalcular indices.
const onChange = event => emit('change', { stepId: props.step.id, event });
</script>

<template>
  <section
    class="flex flex-col w-72 shrink-0 rounded-xl bg-n-alpha-1 max-h-full"
    :aria-label="step.name"
  >
    <header class="flex items-center gap-2 px-3 py-3">
      <span
        class="size-2.5 rounded-full shrink-0"
        :style="{ backgroundColor: step.color }"
        :title="stageLabel"
      />
      <h3 class="text-sm font-medium truncate text-n-slate-12">
        {{ step.name }}
      </h3>
      <span
        class="px-1.5 py-0.5 text-xs rounded-full bg-n-alpha-2 text-n-slate-11"
      >
        {{ tasks.length }}
      </span>
    </header>

    <Draggable
      :list="tasks"
      :disabled="!canEdit"
      group="funnel-tasks"
      item-key="id"
      tag="div"
      class="flex flex-col gap-2 px-2 pb-2 overflow-y-auto grow min-h-16"
      ghost-class="opacity-40"
      drag-class="rotate-1"
      animation="150"
      @change="onChange"
    >
      <template #item="{ element }">
        <FunnelCard :task="element" @open="$emit('openTask', element)" />
      </template>
      <template #footer>
        <p
          v-if="!tasks.length"
          class="px-1 py-6 text-xs text-center text-n-slate-10"
        >
          {{ t('FUNNEL.COLUMN.EMPTY') }}
        </p>
      </template>
    </Draggable>

    <footer v-if="canEdit" class="px-2 pb-2">
      <Button
        variant="ghost"
        color="slate"
        size="sm"
        icon="i-lucide-plus"
        class="w-full"
        justify="start"
        :label="t('FUNNEL.COLUMN.ADD_CARD')"
        @click="$emit('addCard', step)"
      />
    </footer>
  </section>
</template>
