<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Draggable from 'vuedraggable';

import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import FunnelCard from './FunnelCard.vue';
import { formatMoney } from 'dashboard/helper/funnelHelper';
import { useFunnelStore } from 'dashboard/stores/funnel';

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
const funnelStore = useFunnelStore();

const stageLabel = computed(() =>
  t(`FUNNEL.STAGE_TYPE.${(props.step.stageType || 'open').toUpperCase()}`)
);

// Ganho e perdido tambem por icone, e nao so por verde e vermelho: esse par separa por dE 3,9
// em deuteranopia, ou seja, as duas colunas que mais importam num funil sao indistinguiveis para
// quem tem a forma mais comum de daltonismo. O simbolo nao depende de enxergar a diferenca.
const STAGE_ICONS = {
  won: 'i-lucide-circle-check',
  lost: 'i-lucide-circle-x',
};

const stageIcon = computed(() => STAGE_ICONS[props.step.stageType] ?? null);

const stageIconClass = computed(() =>
  props.step.stageType === 'won' ? 'text-n-teal-10' : 'text-n-ruby-9'
);

// Quanto a coluna vale, e nao so quantos cards tem: num funil de vendas e a primeira pergunta de
// quem olha o quadro. Some so o que tem valor; coluna inteira sem valor nao mostra "R$ 0", que
// afirmaria que nada ali vale nada.
const totalValue = computed(() => {
  const sum = props.tasks.reduce((total, task) => {
    const amount = Number(task.value);
    return Number.isFinite(amount) ? total + amount : total;
  }, 0);

  if (!sum) return '';

  return formatMoney(sum, funnelStore.getActiveBoard?.currency || 'BRL');
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
      class="flex flex-col rounded-t-xl"
      :class="canManageSteps ? 'funnel-step-handle cursor-grab' : ''"
      :title="stageLabel"
    >
      <!-- Faixa fina no lugar do bloco saturado. Seis cabecalhos chapados gritavam mais alto que
           os cards, que sao o conteudo; assim a cor agrupa a coluna sem competir. De quebra o
           texto volta a ter contraste garantido contra a superficie neutra, em vez de depender da
           luminancia da cor que o usuario escolheu. -->
      <div
        class="h-[3px] rounded-t-xl"
        :style="{ backgroundColor: step.color }"
      />
      <div class="flex items-center gap-2 px-3 py-2.5 text-n-slate-12">
        <h3 class="text-sm font-semibold truncate">
          {{ step.name }}
        </h3>
        <!-- Depois do nome, e nao antes: a esquerda, o icone empurrava o texto e as duas colunas
             terminais comecavam alguns pixels adiante das outras quatro, desalinhando a fileira
             inteira de cabecalhos. -->
        <Icon
          v-if="stageIcon"
          :icon="stageIcon"
          class="shrink-0 size-3.5"
          :class="stageIconClass"
        />
        <span
          class="px-1.5 py-0.5 text-xs font-medium rounded-full bg-n-alpha-2 text-n-slate-11"
        >
          {{ tasks.length }}
        </span>
        <span
          v-if="totalValue"
          class="text-xs font-medium tabular-nums text-n-slate-11"
        >
          {{ totalValue }}
        </span>
        <div
          v-if="canEdit"
          class="flex items-center gap-0.5 ltr:ml-auto rtl:mr-auto"
        >
          <button
            v-if="canManageSteps"
            type="button"
            class="p-1 rounded text-n-slate-11 hover:bg-n-alpha-2"
            :aria-label="t('FUNNEL.STEP.CONFIGURE')"
            @click="$emit('configure', step)"
          >
            <Icon icon="i-lucide-settings" class="size-3.5" />
          </button>
          <button
            v-if="canEdit"
            type="button"
            class="p-1 rounded text-n-slate-11 hover:bg-n-alpha-2"
            :aria-label="t('FUNNEL.COLUMN.ADD_CARD')"
            @click="$emit('addCard', step)"
          >
            <Icon icon="i-lucide-plus" class="size-3.5" />
          </button>
        </div>
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
