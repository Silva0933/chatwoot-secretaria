<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import ChannelIcon from 'dashboard/components-next/icon/ChannelIcon.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import {
  timeInStep,
  dueState,
  DUE_STATES,
  PRIORITY_META,
} from 'dashboard/helper/funnelHelper';

const props = defineProps({
  task: { type: Object, required: true },
});

defineEmits(['open']);

const { t, locale } = useI18n();

// Prioridade e vencimento usam icone e texto alem da cor: em escala de cinza, ou para quem nao
// distingue vermelho de amarelo, a cor sozinha nao diz nada (PRD 5.2, acessibilidade).
const PRIORITY_CLASSES = {
  ruby: 'text-n-ruby-11 bg-n-ruby-3',
  amber: 'text-n-amber-11 bg-n-amber-3',
  blue: 'text-n-blue-11 bg-n-blue-3',
  slate: 'text-n-slate-11 bg-n-slate-3',
};

const DUE_CLASSES = {
  [DUE_STATES.OVERDUE]: 'text-n-ruby-11 bg-n-ruby-3',
  [DUE_STATES.TODAY]: 'text-n-amber-11 bg-n-amber-3',
  [DUE_STATES.TOMORROW]: 'text-n-amber-11 bg-n-amber-3',
  [DUE_STATES.FUTURE]: 'text-n-slate-11',
};

const MAX_VISIBLE_ASSIGNEES = 3;
const MAX_VISIBLE_LABELS = 3;

const title = computed(() => props.task.title || t('FUNNEL.CARD.NO_TITLE'));

const priority = computed(() => {
  const meta = PRIORITY_META[props.task.priority];
  if (!meta) return null;

  return {
    ...meta,
    classes: PRIORITY_CLASSES[meta.tone],
    label: t(`FUNNEL.PRIORITY.${props.task.priority.toUpperCase()}`),
  };
});

const labels = computed(() => props.task.labels ?? []);
const visibleLabels = computed(() => labels.value.slice(0, MAX_VISIBLE_LABELS));
const hiddenLabelCount = computed(
  () => labels.value.length - visibleLabels.value.length
);

const assignees = computed(() => props.task.assignees ?? []);
const visibleAssignees = computed(() =>
  assignees.value.slice(0, MAX_VISIBLE_ASSIGNEES)
);
const hiddenAssigneeLabel = computed(
  () => `+${assignees.value.length - visibleAssignees.value.length}`
);

const conversations = computed(() => props.task.conversations ?? []);
const contact = computed(() => (props.task.contacts ?? [])[0] ?? null);

// O ChannelIcon do core resolve o glifo a partir de channel_type, provider e medium — os tres
// vem no payload por isso. Reusar significa que um canal novo no Chatwoot aparece aqui sozinho.
const channelInbox = computed(() => {
  const channel = props.task.channel;
  if (!channel) return null;

  return {
    channel_type: channel.channelType,
    provider: channel.provider,
    medium: channel.medium,
    name: channel.name,
  };
});

const stepAge = computed(() => timeInStep(props.task.stepChangedAt));

const due = computed(() => {
  const state = dueState(props.task.dueAt);
  if (!state) return null;

  const date = new Date(props.task.dueAt);
  const relative = {
    [DUE_STATES.OVERDUE]: t('FUNNEL.CARD.OVERDUE'),
    [DUE_STATES.TODAY]: t('FUNNEL.CARD.TODAY'),
    [DUE_STATES.TOMORROW]: t('FUNNEL.CARD.TOMORROW'),
  }[state];

  return {
    state,
    classes: DUE_CLASSES[state],
    isAlert: state !== DUE_STATES.FUTURE,
    // Perto do prazo o quadro diz "Hoje"; longe dele a data exata informa mais que "em 12 dias".
    label:
      relative ??
      date.toLocaleDateString(locale.value.replace('_', '-'), {
        day: '2-digit',
        month: 'short',
      }),
  };
});

const summary = computed(() => props.task.description?.trim() || '');
</script>

<template>
  <div
    class="flex flex-col gap-2 p-3 border rounded-lg cursor-pointer select-none bg-n-solid-1 border-n-weak hover:border-n-slate-6"
    role="button"
    tabindex="0"
    :aria-label="t('FUNNEL.CARD.OPEN')"
    @click="$emit('open', task)"
    @keydown.enter.prevent="$emit('open', task)"
    @keydown.space.prevent="$emit('open', task)"
  >
    <!-- 1. titulo, com o responsavel a direita, como na referencia -->
    <div class="flex items-start justify-between gap-2">
      <span
        class="text-sm font-semibold break-words text-n-slate-12 line-clamp-2"
      >
        {{ title }}
      </span>
      <div
        v-if="assignees.length"
        class="flex items-center shrink-0 -space-x-1.5"
      >
        <Avatar
          v-for="assignee in visibleAssignees"
          :key="assignee.id"
          :name="assignee.name"
          :src="assignee.avatarUrl"
          :size="20"
          rounded-full
          class="ring-1 ring-n-solid-1"
        />
        <span
          v-if="assignees.length > visibleAssignees.length"
          class="flex items-center justify-center text-xs rounded-full size-5 bg-n-slate-3 text-n-slate-11 ring-1 ring-n-solid-1"
        >
          {{ hiddenAssigneeLabel }}
        </span>
      </div>
    </div>

    <!-- 2. resumo -->
    <p v-if="summary" class="text-xs text-n-slate-11 line-clamp-2">
      {{ summary }}
    </p>

    <!-- 3. contato e canal de origem: de onde este atendimento veio -->
    <div v-if="contact || channelInbox" class="flex items-center gap-1.5">
      <div v-if="contact" class="relative shrink-0">
        <Avatar :name="contact.name" :size="20" rounded-full />
        <ChannelIcon
          v-if="channelInbox"
          :inbox="channelInbox"
          use-brand-icon
          class="absolute -bottom-0.5 -right-0.5 size-3 rounded-full bg-n-solid-1"
        />
      </div>
      <span v-if="contact" class="text-xs truncate text-n-slate-11">
        {{ contact.name }}
      </span>
      <span
        v-if="channelInbox && !contact"
        class="flex items-center gap-1 px-1.5 py-0.5 text-xs rounded bg-n-alpha-2 text-n-slate-11"
      >
        <ChannelIcon :inbox="channelInbox" use-brand-icon class="size-3" />
        {{ channelInbox.name }}
      </span>
    </div>

    <!-- 4. etiquetas -->
    <div v-if="labels.length" class="flex flex-wrap gap-1">
      <span
        v-for="label in visibleLabels"
        :key="label.id"
        class="flex items-center gap-1 px-1.5 py-0.5 text-xs rounded bg-n-alpha-2 text-n-slate-11"
      >
        <span
          class="size-2 rounded-sm shrink-0"
          :style="{ backgroundColor: label.color }"
        />
        {{ label.title }}
      </span>
      <span
        v-if="hiddenLabelCount > 0"
        class="px-1.5 py-0.5 text-xs rounded bg-n-alpha-2 text-n-slate-11"
      >
        {{ `+${hiddenLabelCount}` }}
      </span>
    </div>

    <!-- 5. rodape de triagem: prioridade, vencimento, tempo na etapa, conversas -->
    <div class="flex items-center gap-2">
      <span
        v-if="priority"
        class="flex items-center gap-0.5 px-1 py-0.5 text-xs font-medium rounded shrink-0"
        :class="priority.classes"
        :title="priority.label"
      >
        <Icon :icon="priority.icon" class="size-3" />
        {{ priority.label }}
      </span>

      <span
        v-if="due"
        class="flex items-center gap-1 px-1 py-0.5 text-xs rounded shrink-0"
        :class="due.classes"
      >
        <Icon
          :icon="due.isAlert ? 'i-lucide-alert-circle' : 'i-lucide-calendar'"
          class="size-3"
        />
        {{ due.label }}
      </span>

      <div
        class="flex items-center gap-2 text-xs ltr:ml-auto rtl:mr-auto text-n-slate-10"
      >
        <span
          v-if="conversations.length"
          class="flex items-center gap-1"
          :title="t('FUNNEL.ASSOCIATIONS.CONVERSATIONS')"
        >
          <Icon icon="i-lucide-message-square" class="size-3" />
          {{ conversations.length }}
        </span>
        <span
          v-if="stepAge"
          class="flex items-center gap-1"
          :title="t('FUNNEL.CARD.TIME_IN_STEP')"
        >
          <Icon icon="i-lucide-clock" class="size-3" />
          {{ stepAge }}
        </span>
      </div>
    </div>
  </div>
</template>
