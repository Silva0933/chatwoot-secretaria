<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { debounce } from '@chatwoot/utils';
import { OnClickOutside } from '@vueuse/components';

import { useMapGetter } from 'dashboard/composables/store';
import { useFunnelStore } from 'dashboard/stores/funnel';
import { useUISettings } from 'dashboard/composables/useUISettings';
import {
  SORT_OPTIONS,
  TASK_PRIORITIES,
  DUE_FILTERS,
  WAITING_FILTERS,
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
const attributeKey = ref(funnelStore.filters.attributeKey);
const attributeValue = ref(funnelStore.filters.attributeValue);

// Seis selects abertos ocupavam uma linha inteira acima do primeiro card em todo carregamento do
// quadro, e cinco deles estavam em "qualquer" na quase totalidade do tempo. Agora ficam atras de
// um botao que diz quantos estao ligados — e os chips abaixo dizem quais, para nao esconder
// filtro ativo atras de um painel fechado.
const showFilters = ref(false);

const viewName = ref('');
const showSaveView = ref(false);

// Visoes salvas moram nas preferencias do usuario e nao numa tabela. Sao a combinacao de
// filtros de quem esta olhando, nao dado do quadro: uma migration para guardar preferencia
// pessoal seria peso a mais no schema por nada.
const { updateUISettings, uiSettings } = useUISettings();

const savedViews = computed(() => uiSettings.value?.funnel_saved_views ?? []);

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

const dueOptions = computed(() =>
  withAnyOption(
    DUE_FILTERS.map(value => ({
      value,
      label: t(`FUNNEL.FILTERS.DUE.${value.toUpperCase()}`),
    })),
    t('FUNNEL.FILTERS.ANY_DUE')
  )
);

const waitingOptions = computed(() =>
  withAnyOption(
    WAITING_FILTERS.map(value => ({
      value,
      label: t(`FUNNEL.FILTERS.WAITING.${value.toUpperCase()}`),
    })),
    t('FUNNEL.FILTERS.ANY_WAITING')
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
  if (filters.value.due) {
    chips.push({
      key: 'due',
      label: named(dueOptions.value, filters.value.due) ?? filters.value.due,
    });
  }
  if (filters.value.waiting) {
    chips.push({
      key: 'waiting',
      label:
        named(waitingOptions.value, filters.value.waiting) ??
        filters.value.waiting,
    });
  }
  if (filters.value.attributeKey) {
    chips.push({
      key: 'attributeKey',
      label: filters.value.attributeValue
        ? `${filters.value.attributeKey}: ${filters.value.attributeValue}`
        : filters.value.attributeKey,
    });
  }

  return chips;
});

// A busca tem campo proprio na barra, entao o contador do botao conta so o que esta atras dele:
// somar a busca faria o botao dizer "1" com o painel inteiro em "qualquer".
const filterCount = computed(
  () => activeChips.value.filter(chip => chip.key !== 'search').length
);

const setFilter = (key, value) => funnelStore.setFilters({ [key]: value });

// Remover o chip do atributo tem de limpar a chave e o valor: deixar o valor sozinho
// filtraria por nada e o chip nao voltaria para dizer isso.
const clearAttribute = () => {
  attributeKey.value = '';
  attributeValue.value = '';
  funnelStore.setFilters({ attributeKey: '', attributeValue: '' });
};

const clearChip = key =>
  key === 'attributeKey'
    ? clearAttribute()
    : setFilter(key, EMPTY_FILTERS[key]);

const clearAll = () => {
  searchInput.value = '';
  attributeKey.value = '';
  attributeValue.value = '';
  funnelStore.clearFilters();
};

const pushAttribute = debounce(() => {
  funnelStore.setFilters({
    attributeKey: attributeKey.value,
    attributeValue: attributeValue.value,
  });
}, 250);

const saveView = () => {
  const name = viewName.value.trim();
  if (!name) return;

  const views = savedViews.value.filter(view => view.name !== name);
  updateUISettings({
    funnel_saved_views: [
      ...views,
      { name, filters: { ...funnelStore.filters }, sortBy: funnelStore.sortBy },
    ],
  });
  viewName.value = '';
  showSaveView.value = false;
};

const applyView = view => {
  searchInput.value = view.filters?.search ?? '';
  attributeKey.value = view.filters?.attributeKey ?? '';
  attributeValue.value = view.filters?.attributeValue ?? '';
  funnelStore.setFilters({ ...EMPTY_FILTERS, ...view.filters });
  funnelStore.setSortBy(view.sortBy ?? 'waiting');
};

const removeView = name =>
  updateUISettings({
    funnel_saved_views: savedViews.value.filter(view => view.name !== name),
  });

// Buscar a cada tecla refiltraria a lista inteira em cada letra; 250ms cobre a digitacao sem a
// tela parecer travada.
const pushSearch = debounce(value => setFilter('search', value), 250);

watch(searchInput, value => pushSearch(value));
watch([attributeKey, attributeValue], () => pushAttribute());

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
      <div class="relative w-72">
        <Icon
          icon="i-lucide-search"
          class="absolute top-2.5 size-4 text-n-slate-10 ltr:left-3 rtl:right-3"
        />
        <Input
          v-model="searchInput"
          custom-input-class="ltr:pl-9 rtl:pr-9"
          :placeholder="t('FUNNEL.FILTERS.SEARCH_PLACEHOLDER')"
          :aria-label="t('FUNNEL.FILTERS.SEARCH_PLACEHOLDER')"
        />
      </div>

      <OnClickOutside class="relative" @trigger="showFilters = false">
        <Button
          :variant="showFilters || filterCount ? 'faded' : 'ghost'"
          color="slate"
          size="sm"
          icon="i-lucide-list-filter"
          type="button"
          :aria-expanded="showFilters"
          @click="showFilters = !showFilters"
        >
          <span class="min-w-0 truncate">{{ t('FUNNEL.FILTERS.BUTTON') }}</span>
          <span
            v-if="filterCount"
            class="flex items-center justify-center px-1.5 text-xs font-medium rounded-full h-[18px] min-w-[18px] bg-n-blue-9 text-white"
          >
            {{ filterCount }}
          </span>
        </Button>

        <!-- O painel guarda os seis seletores que antes moravam na barra. Abre por cima do
             quadro e nao empurra as colunas para baixo: mexer no filtro nao deve mover o card
             que se estava olhando. -->
        <div
          v-if="showFilters"
          class="absolute z-50 flex flex-col gap-3 p-4 border shadow-lg w-80 top-10 ltr:left-0 rtl:right-0 rounded-xl bg-n-solid-2 border-n-weak"
        >
          <label class="flex flex-col gap-1">
            <span class="text-xs font-medium text-n-slate-11">
              {{ t('FUNNEL.FILTERS.WAITING_LABEL') }}
            </span>
            <Select
              :model-value="filters.waiting"
              :options="waitingOptions"
              :aria-label="t('FUNNEL.FILTERS.WAITING_LABEL')"
              @update:model-value="value => setFilter('waiting', value)"
            />
          </label>

          <label class="flex flex-col gap-1">
            <span class="text-xs font-medium text-n-slate-11">
              {{ t('FUNNEL.FILTERS.AGENT_LABEL') }}
            </span>
            <Select
              :model-value="filters.assigneeId"
              :options="agentOptions"
              :aria-label="t('FUNNEL.FILTERS.AGENT_LABEL')"
              @update:model-value="value => setFilter('assigneeId', value)"
            />
          </label>

          <label class="flex flex-col gap-1">
            <span class="text-xs font-medium text-n-slate-11">
              {{ t('FUNNEL.FILTERS.INBOX_LABEL') }}
            </span>
            <Select
              :model-value="filters.inboxId"
              :options="inboxOptions"
              :aria-label="t('FUNNEL.FILTERS.INBOX_LABEL')"
              @update:model-value="value => setFilter('inboxId', value)"
            />
          </label>

          <label class="flex flex-col gap-1">
            <span class="text-xs font-medium text-n-slate-11">
              {{ t('FUNNEL.FILTERS.PRIORITY_LABEL') }}
            </span>
            <Select
              :model-value="filters.priority"
              :options="priorityOptions"
              :aria-label="t('FUNNEL.FILTERS.PRIORITY_LABEL')"
              @update:model-value="value => setFilter('priority', value)"
            />
          </label>

          <label class="flex flex-col gap-1">
            <span class="text-xs font-medium text-n-slate-11">
              {{ t('FUNNEL.FILTERS.LABEL_LABEL') }}
            </span>
            <Select
              :model-value="filters.labelId"
              :options="labelOptions"
              :aria-label="t('FUNNEL.FILTERS.LABEL_LABEL')"
              @update:model-value="value => setFilter('labelId', value)"
            />
          </label>

          <label class="flex flex-col gap-1">
            <span class="text-xs font-medium text-n-slate-11">
              {{ t('FUNNEL.FILTERS.DUE_LABEL') }}
            </span>
            <Select
              :model-value="filters.due"
              :options="dueOptions"
              :aria-label="t('FUNNEL.FILTERS.DUE_LABEL')"
              @update:model-value="value => setFilter('due', value)"
            />
          </label>

          <div class="h-px bg-n-weak" />

          <div class="flex flex-col gap-1">
            <span class="text-xs font-medium text-n-slate-11">
              {{ t('FUNNEL.FILTERS.ATTRIBUTE_LABEL') }}
            </span>
            <div class="flex gap-2">
              <Input
                v-model="attributeKey"
                class="grow"
                :placeholder="t('FUNNEL.FILTERS.ATTRIBUTE_KEY')"
                :aria-label="t('FUNNEL.FILTERS.ATTRIBUTE_KEY')"
              />
              <Input
                v-model="attributeValue"
                class="grow"
                :placeholder="t('FUNNEL.FILTERS.ATTRIBUTE_VALUE')"
                :aria-label="t('FUNNEL.FILTERS.ATTRIBUTE_VALUE')"
              />
            </div>
          </div>

          <div v-if="savedViews.length" class="flex flex-wrap gap-1.5">
            <span
              v-for="view in savedViews"
              :key="view.name"
              class="flex items-center gap-1 py-0.5 ltr:pl-2 ltr:pr-1 rtl:pr-2 rtl:pl-1 text-xs rounded-md bg-n-alpha-2 text-n-slate-12"
            >
              <button
                type="button"
                class="hover:underline"
                @click="applyView(view)"
              >
                {{ view.name }}
              </button>
              <Button
                variant="ghost"
                color="slate"
                size="xs"
                icon="i-lucide-x"
                :aria-label="t('FUNNEL.FILTERS.REMOVE_VIEW')"
                @click="removeView(view.name)"
              />
            </span>
          </div>

          <div class="flex items-center gap-2">
            <template v-if="showSaveView">
              <Input
                v-model="viewName"
                class="grow"
                :placeholder="t('FUNNEL.FILTERS.VIEW_NAME')"
                :aria-label="t('FUNNEL.FILTERS.VIEW_NAME')"
                @keydown.enter.prevent="saveView"
              />
              <Button
                variant="faded"
                color="slate"
                size="xs"
                :label="t('FUNNEL.FILTERS.SAVE_VIEW')"
                :disabled="!viewName.trim()"
                @click="saveView"
              />
            </template>
            <Button
              v-else-if="hasFilters"
              variant="link"
              color="slate"
              size="xs"
              icon="i-lucide-bookmark"
              :label="t('FUNNEL.FILTERS.SAVE_VIEW')"
              @click="showSaveView = true"
            />
            <div class="grow" />
            <Button
              v-if="hasFilters"
              variant="link"
              color="slate"
              size="xs"
              :label="t('FUNNEL.FILTERS.CLEAR_ALL')"
              @click="clearAll"
            />
          </div>
        </div>
      </OnClickOutside>

      <!-- Os chips ficam na barra, e nao dentro do painel: filtro ativo que so aparece depois de
           abrir um menu e filtro que o operador esquece que ligou. -->
      <span
        v-for="chip in activeChips"
        :key="chip.key"
        class="flex items-center gap-1 py-0.5 ltr:pl-2.5 ltr:pr-1 rtl:pr-2.5 rtl:pl-1 text-xs rounded-full bg-n-alpha-2 text-n-slate-12"
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

      <!-- O contador diz quanto o filtro escondeu: sem ele, uma coluna vazia parece um quadro
           vazio, e o relatorio pede que os contadores respeitem exatamente o filtro. -->
      <span v-if="hasFilters" class="text-xs text-n-slate-10">
        {{
          t('FUNNEL.FILTERS.SHOWING', {
            visible: visibleCount,
            total: totalCount,
          })
        }}
      </span>

      <div class="grow" />

      <div class="flex items-center gap-1.5 shrink-0">
        <Icon icon="i-lucide-arrow-up-down" class="size-4 text-n-slate-10" />
        <Select
          :model-value="funnelStore.sortBy"
          :options="sortOptions"
          :aria-label="t('FUNNEL.SORT.LABEL')"
          class="w-44"
          @update:model-value="value => funnelStore.setSortBy(value)"
        />
      </div>
    </div>
  </div>
</template>
