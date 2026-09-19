<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Draggable from 'vuedraggable';
import { OnClickOutside } from '@vueuse/components';

import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import FunnelCard from './FunnelCard.vue';
import { formatMoney } from 'dashboard/helper/funnelHelper';
import { useFunnelStore } from 'dashboard/stores/funnel';

const props = defineProps({
  step: { type: Object, required: true },
  steps: { type: Array, default: () => [] },
  tasks: { type: Array, default: () => [] },
  canEdit: { type: Boolean, default: false },
  canManageSteps: { type: Boolean, default: false },
  canArchive: { type: Boolean, default: false },
  canDrag: { type: Boolean, default: true },
  isFirst: { type: Boolean, default: false },
  isLast: { type: Boolean, default: false },
});

const emit = defineEmits([
  'change',
  'addCard',
  'openTask',
  'openConversation',
  'configure',
  'moveStep',
  'deleteStep',
  'moveTask',
  'assignTask',
  'setTaskUrgency',
  'archiveTask',
]);

const { t } = useI18n();
const funnelStore = useFunnelStore();

const showMenu = ref(false);

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

// A engrenagem de hoje abre so o dialogo da etapa. As outras linhas sao atalhos que hoje ou nao
// existem ou exigem arrastar — reordenar com seis colunas na tela e dificil com o mouse e
// impossivel sem ele.
const menuItems = computed(() => {
  const items = [
    {
      label: t('FUNNEL.STEP.CONFIGURE'),
      value: 'configure',
      icon: 'i-lucide-settings',
    },
    {
      label: t('FUNNEL.STEP.MENU.ADD_CARD'),
      value: 'addCard',
      icon: 'i-lucide-plus',
    },
    {
      label: t('FUNNEL.STEP.MENU.MOVE_LEFT'),
      value: 'left',
      icon: 'i-lucide-chevron-left',
      disabled: props.isFirst,
    },
    {
      label: t('FUNNEL.STEP.MENU.MOVE_RIGHT'),
      value: 'right',
      icon: 'i-lucide-chevron-right',
      disabled: props.isLast,
    },
  ];

  // Um quadro sem etapa nenhuma nao e um quadro: sem outra etapa para onde mandar os cards, a
  // exclusao nem se oferece.
  if (props.steps.length > 1) {
    items.push({
      label: t('FUNNEL.STEP.DELETE'),
      value: 'delete',
      icon: 'i-lucide-trash-2',
      action: 'delete',
    });
  }

  return items;
});

const MENU_ACTIONS = {
  configure: () => emit('configure', props.step),
  addCard: () => emit('addCard', props.step),
  left: () => emit('moveStep', { step: props.step, direction: -1 }),
  right: () => emit('moveStep', { step: props.step, direction: 1 }),
  delete: () => emit('deleteStep', props.step),
};

const onMenuAction = ({ value }) => {
  showMenu.value = false;
  MENU_ACTIONS[value]?.();
};

// O change do vuedraggable dispara depois de a lista ja ter sido mutada, entao o pai le a
// ordem final direto do array em vez de recalcular indices.
const onChange = event => emit('change', { stepId: props.step.id, event });
</script>

<template>
  <!-- A coluna perdeu a caixa. Seis retangulos com fundo e borda propria competiam com os cards,
       que sao o conteudo; sem ela o que separa as colunas e o espaco, e a cor da etapa cabe numa
       faixa de dois pixels em vez de um bloco. -->
  <section class="flex flex-col w-[19rem] shrink-0 max-h-full overflow-hidden">
    <header
      class="relative flex flex-col gap-1.5 px-1 pb-2 group"
      :class="canManageSteps ? 'funnel-step-handle cursor-grab' : ''"
      :title="stageLabel"
    >
      <div class="flex items-center gap-1.5 text-n-slate-12">
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
        <span class="text-xs tabular-nums text-n-slate-10">
          {{ tasks.length }}
        </span>
        <div class="grow" />
        <span
          v-if="totalValue"
          class="text-xs font-medium tabular-nums text-n-slate-11"
        >
          {{ totalValue }}
        </span>

        <OnClickOutside
          v-if="canManageSteps"
          class="relative shrink-0"
          @trigger="showMenu = false"
        >
          <button
            type="button"
            class="flex items-center justify-center transition-opacity border rounded-md size-6 border-n-weak bg-n-solid-2 text-n-slate-11 hover:text-n-slate-12"
            :class="
              showMenu
                ? 'opacity-100'
                : 'opacity-0 group-hover:opacity-100 focus-visible:opacity-100'
            "
            :aria-label="t('FUNNEL.STEP.MENU.LABEL')"
            :aria-expanded="showMenu"
            @click="showMenu = !showMenu"
          >
            <Icon icon="i-lucide-ellipsis-vertical" class="size-3.5" />
          </button>
          <DropdownMenu
            v-if="showMenu"
            :menu-items="menuItems"
            class="w-56 ltr:right-0 rtl:left-0 top-7"
            @action="onMenuAction"
          />
        </OnClickOutside>
      </div>

      <div class="h-0.5 rounded-sm" :style="{ backgroundColor: step.color }" />
    </header>

    <Draggable
      :list="tasks"
      :disabled="!canDrag"
      group="funnel-tasks"
      item-key="id"
      tag="div"
      class="flex flex-col gap-2 px-1 pb-2 overflow-y-auto grow min-h-8"
      ghost-class="opacity-40"
      drag-class="rotate-1"
      animation="150"
      @change="onChange"
    >
      <template #item="{ element }">
        <FunnelCard
          :task="element"
          :steps="steps"
          :can-archive="canArchive"
          @open="$emit('openTask', element)"
          @open-conversation="$emit('openConversation', $event)"
          @move="$emit('moveTask', { task: element, stepId: $event })"
          @assign="$emit('assignTask', { task: element, userId: $event })"
          @set-urgency="
            $emit('setTaskUrgency', { task: element, priority: $event })
          "
          @archive="$emit('archiveTask', $event)"
        />
      </template>
      <!-- Coluna vazia nao mostra mais meia tela de nada com uma frase no meio: o botao de
           adicionar ocupa 34px e esta exatamente onde o card vai nascer. -->
      <template #footer>
        <button
          v-if="canEdit"
          type="button"
          class="flex items-center justify-center w-full gap-1.5 h-[34px] text-xs border border-dashed rounded-lg shrink-0 border-n-weak text-n-slate-10 hover:text-n-slate-11 hover:border-n-slate-6"
          @click="$emit('addCard', step)"
        >
          <Icon icon="i-lucide-plus" class="size-3.5" />
          {{ t('FUNNEL.COLUMN.ADD') }}
        </button>
        <p
          v-else-if="!tasks.length"
          class="px-1 py-4 text-xs text-center text-n-slate-10"
        >
          {{ t('FUNNEL.COLUMN.EMPTY') }}
        </p>
      </template>
    </Draggable>
  </section>
</template>
