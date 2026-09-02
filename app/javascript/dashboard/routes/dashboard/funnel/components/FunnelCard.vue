<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  task: { type: Object, required: true },
});

defineEmits(['open']);

const { t, locale } = useI18n();

const PRIORITY_CLASSES = {
  low: 'text-n-slate-11 bg-n-slate-3',
  medium: 'text-n-blue-11 bg-n-blue-3',
  high: 'text-n-amber-11 bg-n-amber-3',
  urgent: 'text-n-ruby-11 bg-n-ruby-3',
};

// Mais de tres avatares empilhados viram uma mancha; o resto vira "+N".
const MAX_VISIBLE_ASSIGNEES = 3;

const title = computed(() => props.task.title || t('FUNNEL.CARD.NO_TITLE'));

const priorityClass = computed(
  () => PRIORITY_CLASSES[props.task.priority] || ''
);

const priorityLabel = computed(() =>
  props.task.priority
    ? t(`FUNNEL.PRIORITY.${props.task.priority.toUpperCase()}`)
    : ''
);

const labels = computed(() => props.task.labels ?? []);
const conversations = computed(() => props.task.conversations ?? []);
const assignees = computed(() => props.task.assignees ?? []);
const visibleAssignees = computed(() =>
  assignees.value.slice(0, MAX_VISIBLE_ASSIGNEES)
);
const hiddenAssigneeCount = computed(
  () => assignees.value.length - visibleAssignees.value.length
);
const hiddenAssigneeLabel = computed(() => `+${hiddenAssigneeCount.value}`);

const dueLabel = computed(() => {
  if (!props.task.dueAt) return '';

  const date = new Date(props.task.dueAt);
  if (Number.isNaN(date.getTime())) return '';

  return date.toLocaleDateString(locale.value.replace('_', '-'), {
    day: '2-digit',
    month: 'short',
  });
});
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
    <div class="flex items-start justify-between gap-2">
      <span class="text-sm font-medium break-words text-n-slate-12">
        {{ title }}
      </span>
      <span
        v-if="priorityLabel"
        class="shrink-0 px-1.5 py-0.5 text-xs font-medium rounded"
        :class="priorityClass"
      >
        {{ priorityLabel }}
      </span>
    </div>

    <div v-if="labels.length" class="flex flex-wrap gap-1">
      <span
        v-for="label in labels"
        :key="label.id"
        class="flex items-center gap-1 px-1.5 py-0.5 text-xs rounded bg-n-alpha-2 text-n-slate-11"
      >
        <span
          class="size-2 rounded-sm shrink-0"
          :style="{ backgroundColor: label.color }"
        />
        {{ label.title }}
      </span>
    </div>

    <div class="flex items-center justify-between gap-2">
      <div class="flex items-center gap-3 text-xs text-n-slate-11">
        <span
          v-if="dueLabel"
          class="flex items-center gap-1"
          :class="{ 'text-n-ruby-11': task.overdue }"
          :title="task.overdue ? t('FUNNEL.CARD.OVERDUE') : ''"
        >
          <Icon icon="i-lucide-calendar-clock" class="size-3.5" />
          {{ dueLabel }}
        </span>
        <span v-if="conversations.length" class="flex items-center gap-1">
          <Icon icon="i-lucide-message-square" class="size-3.5" />
          {{ conversations.length }}
        </span>
      </div>

      <div v-if="assignees.length" class="flex items-center -space-x-1.5">
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
          v-if="hiddenAssigneeCount > 0"
          class="flex items-center justify-center text-xs rounded-full size-5 bg-n-slate-3 text-n-slate-11 ring-1 ring-n-solid-1"
        >
          {{ hiddenAssigneeLabel }}
        </span>
      </div>
    </div>
  </div>
</template>
