<script setup>
import { computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';

import { useFunnelStore } from 'dashboard/stores/funnel';

import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({
  taskId: { type: Number, required: true },
});

const { t, locale } = useI18n();
const funnelStore = useFunnelStore();

// Um icone por tipo de evento. O que nao estiver no mapa cai no generico em vez de sumir: a
// trilha e auditoria, e esconder uma linha porque falta um icone seria mentir sobre o historico.
const EVENT_ICONS = {
  'task.moved': 'i-lucide-arrow-right-left',
  'task.assignees_replaced': 'i-lucide-users',
  'task.labels_replaced': 'i-lucide-tag',
  'task.contacts_replaced': 'i-lucide-contact',
  'task.conversation_linked': 'i-lucide-link',
  'task.conversation_promoted': 'i-lucide-star',
  'task.conversation_unlinked': 'i-lucide-unlink',
};

const events = computed(() => funnelStore.taskEvents);
const isFetching = computed(() => funnelStore.getUIFlags.fetchingEvents);

const iconFor = eventType => EVENT_ICONS[eventType] || 'i-lucide-circle-dot';

// O backend pode gravar tipos que esta versao da interface ainda nao conhece; nesse caso mostra
// a chave crua, que ainda diz mais do que uma linha em branco.
const labelFor = eventType => {
  const key = `FUNNEL.ACTIVITY.TYPES.${eventType.replace('task.', '').toUpperCase()}`;
  const translated = t(key);
  return translated === key ? eventType : translated;
};

const timestampFor = createdAt => {
  const date = new Date(createdAt);
  if (Number.isNaN(date.getTime())) return '';

  return date.toLocaleString(locale.value.replace('_', '-'), {
    day: '2-digit',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
  });
};

// Quem e quando numa linha so, montada aqui: o separador entre os dois e texto, e texto solto
// no template e o que a regra de i18n proibe.
const metaFor = event =>
  `${event.actor?.name || t('FUNNEL.ACTIVITY.SYSTEM')} · ${timestampFor(event.createdAt)}`;

onMounted(() => {
  funnelStore.fetchTaskEvents({ id: props.taskId }).catch(() => {});
});
</script>

<template>
  <div class="flex flex-col gap-2">
    <span class="text-sm font-medium text-n-slate-12">
      {{ t('FUNNEL.ACTIVITY.TITLE') }}
    </span>

    <div v-if="isFetching" class="flex justify-center py-4">
      <Spinner />
    </div>

    <p v-else-if="!events.length" class="text-xs text-n-slate-10">
      {{ t('FUNNEL.ACTIVITY.EMPTY') }}
    </p>

    <ul v-else class="flex flex-col gap-2 overflow-y-auto max-h-64">
      <li
        v-for="event in events"
        :key="event.id"
        class="flex items-start gap-2 text-xs text-n-slate-11"
      >
        <Icon
          :icon="iconFor(event.eventType)"
          class="mt-0.5 size-3.5 shrink-0"
        />
        <div class="flex flex-col">
          <span class="text-n-slate-12">{{ labelFor(event.eventType) }}</span>
          <span>{{ metaFor(event) }}</span>
        </div>
      </li>
    </ul>
  </div>
</template>
