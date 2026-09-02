<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { debounce } from '@chatwoot/utils';

import { useMapGetter } from 'dashboard/composables/store';
import { useFunnelStore } from 'dashboard/stores/funnel';
import {
  SORT_OPTIONS,
  TASK_PRIORITIES,
  EMPTY_FILTERS,
} from 'dashboard/helper/funnelHelper';

import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';

const { t } = useI18n();
const funnelStore = useFunnelStore();

const agents = useMapGetter('agents/getVerifiedAgents');
const accountLabels = useMapGetter('labels/getLabels');
const inboxes = useMapGetter('inboxes/getInboxes');

const searchInput = ref(funnelStore.filters.search);

const filters = computed(() => funnelStore.filters);
const hasFilters = computed(() => funnelStore.hasFilters);
const visibleCount = computed(() => funnelStore.getFilteredTasks.length);
const totalCount = computed(() => funnelStore.tasks.length);

// null como valor de "todos": o Select trata string vazia como ausencia de escolha, e um id
// nulo e exatamente o que filterTasks entende por filtro desligado.
const withAnyOption = (options, anyLabel) => [
  { value: null, label: anyLabel },
  ...options,
];

const agentOptions = computed(() =>
  withAnyOption(
    (agents.value ?? []).map(agent => ({ value: agent.id, label: agent.name })),
    t('FUNNEL.FILTERS.ANY_AGENT')
  )
);

const inboxOptions = computed(() =>
  withAnyOption(
    (inboxes.value ?? []).map(inbox => ({
      value: inbox.id,
      label: inbox.name,
    })),
    t('FUNNEL.FILTERS.ANY_INBOX')
  )
);

const labelOptions = computed(() =>
  withAnyOption(
    (accountLabels.value ?? []).map(label => ({
      value: label.id,
      label: label.title,
    })),
    t('FUNNEL.FILTERS.ANY_LABEL')
  )
);

const priorityOptions = computed(() =>
  withAnyOption(
    TASK_PRIORITIES.map(priority => ({
      value: priority,
      label: t(`FUNNEL.PRIORITY.${priority.toUpperCase()}`),
    })),
    t('FUNNEL.FILTERS.ANY_PRIORITY')
  )
);

const sortOptions = computed(() =>
  SORT_OPTIONS.map(option => ({
    value: option,
    label: t(`FUNNEL.SORT.${option.toUpperCase()}`),
  }))
);

// Um chip por filtro ligado, cada um removivel sozinho: com quatro filtros combinados, so o
// "limpar tudo" obrigaria a refazer os outros tres para trocar um.
const activeChips = computed(() => {
  const chips = [];
  const { search, assigneeId, inboxId, priority, labelId } = filters.value;

  if (search) chips.push({ key: 'search', label: `"${search}"` });

  const named = (options, value) =>
    options.find(option => option.value === value)?.label;

  if (assigneeId) {
    chips.push({
      key: 'assigneeId',
      label: named(agentOptions.value, assigneeId) ?? String(assigneeId),
    });
  }
  if (inboxId) {
    chips.push({
      key: 'inboxId',
      label: named(inboxOptions.value, inboxId) ?? String(inboxId),
    });
  }
  if (priority) {
    chips.push({
      key: 'priority',
      label: named(priorityOptions.value, priority) ?? priority,
    });
  }
  if (labelId) {
    chips.push({
      key: 'labelId',
      label: named(labelOptions.value, labelId) ?? String(labelId),
    });
  }

  return chips;
});

const setFilter = (key, value) => funnelStore.setFilters({ [key]: value });

const clearChip = key => setFilter(key, EMPTY_FILTERS[key]);

const clearAll = () => {
  searchInput.value = '';
  funnelStore.clearFilters();
};

// Buscar a cada tecla refiltraria a lista inteira em cada letra; 250ms cobre a digitacao sem a
// tela parecer travada.
const pushSearch = debounce(value => setFilter('search', value), 250);

watch(searchInput, value => pushSearch(value));

// A busca tambem chega pela URL, entao o campo precisa acompanhar o estado e nao so alimenta-lo.
watch(
  () => filters.value.search,
  value => {
    if (value !== searchInput.value) searchInput.value = value;
  }
);
</script>

<template>
  <div class="flex flex-col gap-2 px-6 pb-3">
    <div class="flex flex-wrap items-center gap-2">
      <Input
        v-model="searchInput"
        class="w-56"
        :placeholder="t('FUNNEL.FILTERS.SEARCH_PLACEHOLDER')"
        :aria-label="t('FUNNEL.FILTERS.SEARCH_PLACEHOLDER')"
      />

      <Select
        :model-value="filters.assigneeId"
        :options="agentOptions"
        :aria-label="t('FUNNEL.FILTERS.ANY_AGENT')"
        class="w-40"
        @update:model-value="value => setFilter('assigneeId', value)"
      />

      <Select
        :model-value="filters.inboxId"
        :options="inboxOptions"
        :aria-label="t('FUNNEL.FILTERS.ANY_INBOX')"
        class="w-40"
        @update:model-value="value => setFilter('inboxId', value)"
      />

      <Select
        :model-value="filters.priority"
        :options="priorityOptions"
        :aria-label="t('FUNNEL.FILTERS.ANY_PRIORITY')"
        class="w-36"
        @update:model-value="value => setFilter('priority', value)"
      />

      <Select
        :model-value="filters.labelId"
        :options="labelOptions"
        :aria-label="t('FUNNEL.FILTERS.ANY_LABEL')"
        class="w-36"
        @update:model-value="value => setFilter('labelId', value)"
      />

      <div class="flex items-center gap-1.5 ltr:ml-auto rtl:mr-auto">
        <Icon icon="i-lucide-arrow-up-down" class="size-4 text-n-slate-11" />
        <Select
          :model-value="funnelStore.sortBy"
          :options="sortOptions"
          :aria-label="t('FUNNEL.SORT.LABEL')"
          class="w-44"
          @update:model-value="value => funnelStore.setSortBy(value)"
        />
      </div>
    </div>

    <div v-if="hasFilters" class="flex flex-wrap items-center gap-2">
      <span
        v-for="chip in activeChips"
        :key="chip.key"
        class="flex items-center gap-1 py-0.5 ltr:pl-2 ltr:pr-1 rtl:pr-2 rtl:pl-1 text-xs rounded-md bg-n-alpha-2 text-n-slate-12"
      >
        {{ chip.label }}
        <Button
          variant="ghost"
          color="slate"
          size="xs"
          icon="i-lucide-x"
          :aria-label="t('FUNNEL.FILTERS.CLEAR_ONE')"
          @click="clearChip(chip.key)"
        />
      </span>

      <Button
        variant="link"
        color="slate"
        size="xs"
        :label="t('FUNNEL.FILTERS.CLEAR_ALL')"
        @click="clearAll"
      />

      <!-- O contador diz quanto o filtro escondeu: sem ele, uma coluna vazia parece um quadro
           vazio, e o relatorio pede que os contadores respeitem exatamente o filtro. -->
      <span class="text-xs ltr:ml-auto rtl:mr-auto text-n-slate-10">
        {{
          t('FUNNEL.FILTERS.SHOWING', {
            visible: visibleCount,
            total: totalCount,
          })
        }}
      </span>
    </div>
  </div>
</template>
