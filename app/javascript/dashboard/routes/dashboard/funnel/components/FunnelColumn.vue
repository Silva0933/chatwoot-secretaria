<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Draggable from 'vuedraggable';

import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import FunnelCard from './FunnelCard.vue';

const props = defineProps({
  step: { type: Object, required: true },
  tasks: { type: Array, default: () => [] },
  canEdit: { type: Boolean, default: false },
  canManageSteps: { type: Boolean, default: false },
  canDrag: { type: Boolean, default: true },
});

const emit = defineEmits([
  'change',
  'addCard',
  'openTask',
  'openConversation',
  'configure',
]);

const { t } = useI18n();

const stageLabel = computed(() =>
  t(`FUNNEL.STAGE_TYPE.${(props.step.stageType || 'open').toUpperCase()}`)
);

// A cor da etapa e escolhida pelo usuario, entao o texto por cima dela nao pode ser fixo: sobre
// amarelo, branco some. A luminancia decide, com os pesos que o olho da a cada canal.
const headerTextClass = computed(() => {
  const hex = (props.step.color || '#6b7280').replace('#', '');
  const full =
    hex.length === 3
      ? hex
          .split('')
          .map(character => character + character)
          .join('')
      : hex;
  const [red, green, blue] = [0, 2, 4].map(start =>
    parseInt(full.slice(start, start + 2), 16)
  );
  const luminance = (0.299 * red + 0.587 * green + 0.114 * blue) / 255;

  return luminance > 0.6 ? 'text-n-slate-12' : 'text-white';
});

// O change do vuedraggable dispara depois de a lista ja ter sido mutada, entao o pai le a
// ordem final direto do array em vez de recalcular indices.
const onChange = event => emit('change', { stepId: props.step.id, event });
</script>

<template>
  <section
    class="flex flex-col w-[19rem] shrink-0 rounded-xl bg-n-alpha-1 max-h-full overflow-hidden"
    :aria-label="step.name"
  >
    <header
      class="flex items-center gap-2 px-3 py-2.5 rounded-t-xl"
      :class="[
        headerTextClass,
        canManageSteps ? 'funnel-step-handle cursor-grab' : '',
      ]"
      :style="{ backgroundColor: step.color }"
      :title="stageLabel"
    >
      <h3 class="text-sm font-semibold truncate">
        {{ step.name }}
      </h3>
      <span class="px-1.5 py-0.5 text-xs font-medium rounded-full bg-black/20">
        {{ tasks.length }}
      </span>
      <div
        v-if="canEdit"
        class="flex items-center gap-0.5 ltr:ml-auto rtl:mr-auto"
      >
        <button
          v-if="canManageSteps"
          type="button"
          class="p-1 rounded hover:bg-black/20"
          :aria-label="t('FUNNEL.STEP.CONFIGURE')"
          @click="$emit('configure', step)"
        >
          <Icon icon="i-lucide-settings" class="size-3.5" />
        </button>
        <button
          v-if="canEdit"
          type="button"
          class="p-1 rounded hover:bg-black/20"
          :aria-label="t('FUNNEL.COLUMN.ADD_CARD')"
          @click="$emit('addCard', step)"
        >
          <Icon icon="i-lucide-plus" class="size-3.5" />
        </button>
      </div>
    </header>

    <Draggable
      :list="tasks"
      :disabled="!canDrag"
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
        <FunnelCard
          :task="element"
          @open="$emit('openTask', element)"
          @open-conversation="$emit('openConversation', $event)"
        />
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
