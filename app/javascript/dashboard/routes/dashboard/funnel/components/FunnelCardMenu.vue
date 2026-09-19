<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import { useMapGetter } from 'dashboard/composables/store';
import { URGENCY_META } from 'dashboard/helper/funnelHelper';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  task: { type: Object, required: true },
  steps: { type: Array, default: () => [] },
  hasConversation: { type: Boolean, default: false },
  canArchive: { type: Boolean, default: false },
});

const emit = defineEmits([
  'edit',
  'openConversation',
  'move',
  'assign',
  'setUrgency',
  'archive',
  'close',
]);

const { t } = useI18n();
const agents = useMapGetter('agents/getVerifiedAgents');

// O menu troca de painel em vez de abrir um submenu flutuante. Um segundo balao preso na borda
// do card sai da tela na ultima coluna do quadro, que e justamente onde "mover para a etapa
// seguinte" e mais usado; trocar o conteudo do mesmo balao nao tem essa borda.
const panel = ref('root');

// As tres urgencias do quadro contra as quatro prioridades do card. 'medium' e o que "Normal"
// grava, e baixa conta como normal na hora de marcar qual esta ativa: as duas nao desenham nada
// no card, entao mostrar so uma delas como selecionada diria que a outra e alguma coisa.
const URGENCY_CHOICES = [
  { value: 'medium', icon: 'i-lucide-minus', matches: ['medium', 'low', null] },
  { value: 'high', icon: URGENCY_META.high.icon, matches: ['high'] },
  { value: 'urgent', icon: URGENCY_META.urgent.icon, matches: ['urgent'] },
];

const rootItems = computed(() => {
  const items = [
    {
      label: t('FUNNEL.CARD.MENU.EDIT'),
      value: 'edit',
      icon: 'i-lucide-pencil',
    },
  ];

  // Sem conversa vinculada nao ha para onde navegar, e uma linha que nao leva a lugar nenhum
  // pesa mais do que a ausencia dela.
  if (props.hasConversation) {
    items.push({
      label: t('FUNNEL.CARD.MENU.OPEN_CONVERSATION'),
      value: 'conversation',
      icon: 'i-lucide-message-square',
    });
  }

  items.push(
    {
      label: t('FUNNEL.CARD.MENU.MOVE'),
      value: 'step',
      icon: 'i-lucide-arrow-right',
      panel: true,
    },
    {
      label: t('FUNNEL.CARD.MENU.ASSIGN'),
      value: 'assignee',
      icon: 'i-lucide-user-round',
      panel: true,
    },
    {
      label: t('FUNNEL.CARD.MENU.URGENCY'),
      value: 'urgency',
      icon: 'i-lucide-chevron-up',
      panel: true,
    }
  );

  if (props.canArchive) {
    items.push({
      label: t('FUNNEL.CARD.MENU.ARCHIVE'),
      value: 'archive',
      icon: 'i-lucide-archive',
      // 'delete' e o que o DropdownMenu pinta em rubi; arquivar e a acao destrutiva daqui.
      action: 'delete',
    });
  }

  return items;
});

const backItem = computed(() => ({
  label: t('FUNNEL.CARD.MENU.BACK'),
  value: 'back',
  icon: 'i-lucide-chevron-left',
}));

const stepItems = computed(() => [
  backItem.value,
  ...props.steps.map(step => ({
    label: step.name,
    value: step.id,
    icon: 'i-lucide-square',
    iconColor: step.color,
    isSelected: step.id === props.task.funnelStepId,
  })),
]);

const assigneeItems = computed(() => {
  const assigned = new Set((props.task.assignees ?? []).map(user => user.id));

  return [
    backItem.value,
    {
      label: t('FUNNEL.CARD.MENU.UNASSIGN'),
      value: null,
      icon: 'i-lucide-user-round-x',
    },
    ...(agents.value ?? []).map(agent => ({
      label: agent.name,
      value: agent.id,
      thumbnail: { name: agent.name, src: agent.thumbnail },
      isSelected: assigned.has(agent.id),
    })),
  ];
});

const urgencyItems = computed(() => [
  backItem.value,
  ...URGENCY_CHOICES.map(choice => ({
    label: t(`FUNNEL.URGENCY.${choice.value.toUpperCase()}`),
    value: choice.value,
    icon: choice.icon,
    isSelected: choice.matches.includes(props.task.priority ?? null),
  })),
]);

const menuItems = computed(
  () =>
    ({
      step: stepItems.value,
      assignee: assigneeItems.value,
      urgency: urgencyItems.value,
    })[panel.value] ?? rootItems.value
);

// A busca so aparece na lista de agentes: e a unica que cresce com o tamanho da conta. Etapas
// sao seis e urgencias sao tres.
const showSearch = computed(() => panel.value === 'assignee');

const ROOT_ACTIONS = {
  edit: () => emit('edit'),
  conversation: () => emit('openConversation'),
  archive: () => emit('archive'),
};

const onAction = ({ value, panel: isPanel }) => {
  if (value === 'back') {
    panel.value = 'root';
    return;
  }

  if (panel.value === 'root') {
    if (isPanel) {
      panel.value = value;
      return;
    }

    ROOT_ACTIONS[value]?.();
    emit('close');
    return;
  }

  if (panel.value === 'step') emit('move', value);
  if (panel.value === 'assignee') emit('assign', value);
  if (panel.value === 'urgency') emit('setUrgency', value);

  emit('close');
};
</script>

<template>
  <DropdownMenu
    :menu-items="menuItems"
    :show-search="showSearch"
    :search-placeholder="t('FUNNEL.CARD.MENU.SEARCH_AGENT')"
    class="w-56 ltr:right-0 rtl:left-0 top-7"
    @action="onAction"
  >
    <!-- A cor da etapa no lugar do glifo: e como a coluna se identifica no quadro, entao e por
         ela que se reconhece o destino na lista. -->
    <template #icon="{ item }">
      <span
        v-if="item.iconColor"
        class="rounded-sm size-2.5 shrink-0"
        :style="{ backgroundColor: item.iconColor }"
      />
      <Icon v-else-if="item.icon" :icon="item.icon" class="shrink-0 size-3.5" />
    </template>
    <template #trailing-icon="{ item }">
      <Icon
        v-if="item.panel"
        icon="i-lucide-chevron-right"
        class="shrink-0 size-3.5 ltr:ml-auto rtl:mr-auto text-n-slate-10"
      />
    </template>
  </DropdownMenu>
</template>
