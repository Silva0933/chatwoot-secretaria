<script setup>
import { computed, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import { useAlert } from 'dashboard/composables';
import { useMapGetter } from 'dashboard/composables/store';
import { useFunnelStore } from 'dashboard/stores/funnel';
import {
  AUTOMATION_RULES,
  BOARD_MEMBER_ROLES,
  VISIBILITY_SCOPES,
} from 'dashboard/helper/funnelHelper';

import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import TagMultiSelectComboBox from 'dashboard/components-next/combobox/TagMultiSelectComboBox.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';

const props = defineProps({
  board: { type: Object, default: null },
});

const emit = defineEmits(['saveBoard']);

const { t } = useI18n();
const funnelStore = useFunnelStore();

const agents = useMapGetter('agents/getVerifiedAgents');
const inboxes = useMapGetter('inboxes/getInboxes');

const dialogRef = ref(null);
const form = reactive({ name: '', description: '', currency: 'BRL' });
const memberIds = ref([]);
const inboxIds = ref([]);
const roles = reactive({});
const automations = reactive({});

const isSaving = computed(() => funnelStore.getUIFlags.savingBoardSettings);

const agentOptions = computed(() =>
  (agents.value ?? []).map(agent => ({ value: agent.id, label: agent.name }))
);

const inboxOptions = computed(() =>
  (inboxes.value ?? []).map(inbox => ({ value: inbox.id, label: inbox.name }))
);

const roleOptions = computed(() =>
  BOARD_MEMBER_ROLES.map(role => ({
    value: role,
    label: t(`FUNNEL.SETTINGS.ROLES.${role.toUpperCase()}`),
  }))
);

const scopeOptions = computed(() =>
  VISIBILITY_SCOPES.map(scope => ({
    value: scope,
    label: t(`FUNNEL.SETTINGS.SCOPES.${scope.toUpperCase()}`),
  }))
);

const nameFor = id =>
  agentOptions.value.find(option => option.value === id)?.label ?? String(id);

const syncFromBoard = () => {
  const board = props.board;
  if (!board) return;

  form.name = board.name ?? '';
  form.description = board.description ?? '';
  form.currency = board.currency ?? 'BRL';
  memberIds.value = (board.members ?? []).map(member => member.userId);
  inboxIds.value = board.inboxIds ?? [];

  AUTOMATION_RULES.forEach(rule => {
    automations[rule] = Boolean(board.automationSettings?.[rule]);
  });

  (board.members ?? []).forEach(member => {
    roles[member.userId] = {
      role: member.role,
      visibilityScope: member.visibilityScope,
    };
  });
};

// Agente recem-marcado ainda nao tem papel: entra como member com visao total, que e o caso
// comum, e o operador ajusta se quiser restringir.
watch(memberIds, ids => {
  ids.forEach(id => {
    roles[id] ||= { role: 'member', visibilityScope: 'all_tasks' };
  });
});

watch(() => props.board, syncFromBoard, { immediate: true, deep: true });

const open = () => {
  syncFromBoard();
  dialogRef.value?.open();
};

const close = () => dialogRef.value?.close();

const save = async () => {
  if (!form.name.trim()) return;

  try {
    emit('saveBoard', {
      id: props.board.id,
      name: form.name.trim(),
      description: form.description.trim() || null,
      currency: form.currency.trim().toUpperCase(),
      automationSettings: { ...automations },
    });

    await funnelStore.replaceBoardMembers({
      members: memberIds.value.map(id => ({
        user_id: id,
        role: roles[id]?.role ?? 'member',
        visibility_scope: roles[id]?.visibilityScope ?? 'all_tasks',
      })),
    });
    await funnelStore.replaceBoardInboxes({ inboxIds: inboxIds.value });

    useAlert(t('FUNNEL.SETTINGS.SAVED'));
    close();
  } catch (error) {
    useAlert(error.message);
  }
};

defineExpose({ open, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="2xl"
    overflow-y-auto
    :title="t('FUNNEL.SETTINGS.TITLE')"
    :confirm-button-label="t('FUNNEL.SETTINGS.SAVE')"
    :cancel-button-label="t('FUNNEL.SETTINGS.CANCEL')"
    :is-loading="isSaving"
    :disable-confirm-button="!form.name.trim()"
    @confirm="save"
  >
    <div class="flex flex-col gap-5">
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
        <Input
          v-model="form.name"
          class="sm:col-span-2"
          :label="t('FUNNEL.BOARD_DIALOG.NAME_LABEL')"
          :disabled="isSaving"
        />
        <Input
          v-model="form.currency"
          :label="t('FUNNEL.SETTINGS.CURRENCY_LABEL')"
          :message="t('FUNNEL.SETTINGS.CURRENCY_HINT')"
          :disabled="isSaving"
        />
      </div>

      <TextArea
        v-model="form.description"
        :label="t('FUNNEL.BOARD_DIALOG.DESCRIPTION_LABEL')"
        :disabled="isSaving"
        :max-length="280"
        auto-height
      />

      <section class="flex flex-col gap-2">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('FUNNEL.SETTINGS.MEMBERS') }}
        </span>
        <p class="text-xs text-n-slate-10">
          {{ t('FUNNEL.SETTINGS.MEMBERS_HINT') }}
        </p>
        <TagMultiSelectComboBox
          v-model="memberIds"
          :options="agentOptions"
          :disabled="isSaving"
          :placeholder="t('FUNNEL.SETTINGS.MEMBERS_PLACEHOLDER')"
          :search-placeholder="t('FUNNEL.ASSOCIATIONS.SEARCH')"
          :empty-state="t('FUNNEL.ASSOCIATIONS.NO_AGENTS')"
        />

        <ul v-if="memberIds.length" class="flex flex-col gap-2 mt-1">
          <li
            v-for="id in memberIds"
            :key="id"
            class="grid items-center grid-cols-1 gap-2 sm:grid-cols-3"
          >
            <span class="text-sm truncate text-n-slate-12">{{
              nameFor(id)
            }}</span>
            <Select
              v-model="roles[id].role"
              :options="roleOptions"
              :disabled="isSaving"
              :aria-label="t('FUNNEL.SETTINGS.ROLE_LABEL')"
            />
            <Select
              v-model="roles[id].visibilityScope"
              :options="scopeOptions"
              :disabled="isSaving"
              :aria-label="t('FUNNEL.SETTINGS.SCOPE_LABEL')"
            />
          </li>
        </ul>
      </section>

      <section class="flex flex-col gap-2">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('FUNNEL.AUTOMATIONS.TITLE') }}
        </span>
        <p class="text-xs text-n-slate-10">
          {{ t('FUNNEL.AUTOMATIONS.HINT') }}
        </p>
        <label
          v-for="rule in AUTOMATION_RULES"
          :key="rule"
          class="flex items-start gap-2 text-sm cursor-pointer text-n-slate-12"
        >
          <input
            v-model="automations[rule]"
            type="checkbox"
            class="mt-1 accent-n-brand"
            :disabled="isSaving"
          />
          <span class="flex flex-col">
            {{ t(`FUNNEL.AUTOMATIONS.RULES.${rule.toUpperCase()}`) }}
          </span>
        </label>
      </section>

      <section class="flex flex-col gap-2">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('FUNNEL.SETTINGS.INBOXES') }}
        </span>
        <p class="text-xs text-n-slate-10">
          {{ t('FUNNEL.SETTINGS.INBOXES_HINT') }}
        </p>
        <TagMultiSelectComboBox
          v-model="inboxIds"
          :options="inboxOptions"
          :disabled="isSaving"
          :placeholder="t('FUNNEL.SETTINGS.INBOXES_PLACEHOLDER')"
          :search-placeholder="t('FUNNEL.ASSOCIATIONS.SEARCH')"
          :empty-state="t('FUNNEL.SETTINGS.NO_INBOXES')"
        />
      </section>
    </div>

    <template #footer>
      <div class="flex items-center justify-end w-full gap-2">
        <Button
          variant="faded"
          color="slate"
          :label="t('FUNNEL.SETTINGS.CANCEL')"
          type="button"
          @click="close"
        />
        <Button
          color="blue"
          :label="t('FUNNEL.SETTINGS.SAVE')"
          type="submit"
          :disabled="!form.name.trim() || isSaving"
          :is-loading="isSaving"
        />
      </div>
    </template>
  </Dialog>
</template>
