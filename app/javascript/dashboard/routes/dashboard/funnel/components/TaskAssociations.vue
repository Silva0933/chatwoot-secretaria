<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { debounce } from '@chatwoot/utils';

import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useMapGetter } from 'dashboard/composables/store';
import { useFunnelStore } from 'dashboard/stores/funnel';
import { frontendURL, conversationUrl } from 'dashboard/helper/URLHelper';
import ContactAPI from 'dashboard/api/contacts';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TagMultiSelectComboBox from 'dashboard/components-next/combobox/TagMultiSelectComboBox.vue';

const props = defineProps({
  task: { type: Object, required: true },
  canEdit: { type: Boolean, default: false },
});

const { t } = useI18n();
const { accountId } = useAccount();
const funnelStore = useFunnelStore();

const agents = useMapGetter('agents/getVerifiedAgents');
const accountLabels = useMapGetter('labels/getLabels');

const conversationInput = ref('');
const contactQuery = ref('');
const contactResults = ref([]);
const isSearchingContacts = ref(false);

const isSaving = computed(() => funnelStore.getUIFlags.updatingAssociations);

const agentOptions = computed(() =>
  (agents.value ?? []).map(agent => ({ value: agent.id, label: agent.name }))
);

const labelOptions = computed(() =>
  (accountLabels.value ?? []).map(label => ({
    value: label.id,
    label: label.title,
  }))
);

const selectedAgentIds = computed(() =>
  (props.task.assignees ?? []).map(assignee => assignee.id)
);

const selectedLabelIds = computed(() =>
  (props.task.labels ?? []).map(label => label.id)
);

const contacts = computed(() => props.task.contacts ?? []);
const conversations = computed(() => props.task.conversations ?? []);

const save = async (kind, ids) => {
  try {
    await funnelStore.replaceAssociation({ id: props.task.id, kind, ids });
  } catch (error) {
    useAlert(error.message);
  }
};

const onAgentsChange = ids => save('assignees', ids);
const onLabelsChange = ids => save('labels', ids);

// O contato entra e sai pela mesma troca de conjunto dos outros: a lista atual mais ou menos um.
const addContact = contact => {
  contactQuery.value = '';
  contactResults.value = [];
  if (contacts.value.some(item => item.id === contact.id)) return;

  save('contacts', [...contacts.value.map(item => item.id), contact.id]);
};

const removeContact = contact =>
  save(
    'contacts',
    contacts.value.map(item => item.id).filter(id => id !== contact.id)
  );

const searchContacts = debounce(async query => {
  if (!query.trim()) {
    contactResults.value = [];
    return;
  }

  isSearchingContacts.value = true;
  try {
    const { data } = await ContactAPI.search(query.trim());
    contactResults.value = (data.payload ?? []).slice(0, 5);
  } catch (error) {
    contactResults.value = [];
  } finally {
    isSearchingContacts.value = false;
  }
}, 300);

const onContactQuery = value => {
  contactQuery.value = value;
  searchContacts(value);
};

const linkConversation = async () => {
  const displayId = Number(conversationInput.value);
  if (!displayId) return;

  try {
    await funnelStore.linkConversation({ id: props.task.id, displayId });
    conversationInput.value = '';
  } catch (error) {
    useAlert(error.message);
  }
};

const promoteConversation = async displayId => {
  try {
    await funnelStore.promoteConversation({ id: props.task.id, displayId });
  } catch (error) {
    useAlert(error.message);
  }
};

const unlinkConversation = async displayId => {
  try {
    await funnelStore.unlinkConversation({ id: props.task.id, displayId });
  } catch (error) {
    useAlert(error.message);
  }
};

// Abre a conversa na caixa de entrada dela, e nao numa aba do card: o agente quer responder,
// e e la que estao o editor e o historico.
const conversationLink = conversation =>
  frontendURL(
    conversationUrl({
      accountId: accountId.value,
      activeInbox: conversation.inboxId,
      id: conversation.id,
    })
  );
</script>

<template>
  <div class="flex flex-col gap-5">
    <section class="flex flex-col gap-2">
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('FUNNEL.TASK.ASSIGNEES') }}
      </span>
      <TagMultiSelectComboBox
        :options="agentOptions"
        :model-value="selectedAgentIds"
        :disabled="!canEdit || isSaving"
        :placeholder="t('FUNNEL.ASSOCIATIONS.ASSIGNEES_PLACEHOLDER')"
        :search-placeholder="t('FUNNEL.ASSOCIATIONS.SEARCH')"
        :empty-state="t('FUNNEL.ASSOCIATIONS.NO_AGENTS')"
        @update:model-value="onAgentsChange"
      />
    </section>

    <section class="flex flex-col gap-2">
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('FUNNEL.TASK.LABELS') }}
      </span>
      <TagMultiSelectComboBox
        :options="labelOptions"
        :model-value="selectedLabelIds"
        :disabled="!canEdit || isSaving"
        :placeholder="t('FUNNEL.ASSOCIATIONS.LABELS_PLACEHOLDER')"
        :search-placeholder="t('FUNNEL.ASSOCIATIONS.SEARCH')"
        :empty-state="t('FUNNEL.ASSOCIATIONS.NO_LABELS')"
        @update:model-value="onLabelsChange"
      />
    </section>

    <section class="flex flex-col gap-2">
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('FUNNEL.TASK.CONTACTS') }}
      </span>
      <div v-if="contacts.length" class="flex flex-wrap gap-2">
        <span
          v-for="contact in contacts"
          :key="contact.id"
          class="flex items-center gap-1.5 py-1 ltr:pl-2 ltr:pr-1 rtl:pr-2 rtl:pl-1 text-sm rounded-md bg-n-alpha-2 text-n-slate-12"
        >
          <Avatar :name="contact.name" :size="18" rounded-full />
          {{ contact.name }}
          <Button
            v-if="canEdit"
            variant="ghost"
            color="slate"
            size="xs"
            icon="i-lucide-x"
            :aria-label="t('FUNNEL.ASSOCIATIONS.REMOVE_CONTACT')"
            :disabled="isSaving"
            @click="removeContact(contact)"
          />
        </span>
      </div>
      <div v-if="canEdit" class="relative">
        <Input
          :model-value="contactQuery"
          :placeholder="t('FUNNEL.ASSOCIATIONS.CONTACT_PLACEHOLDER')"
          :disabled="isSaving"
          @update:model-value="onContactQuery"
        />
        <ul
          v-if="contactResults.length"
          class="absolute z-20 w-full mt-1 overflow-y-auto border rounded-lg shadow-lg bg-n-solid-1 border-n-weak max-h-48"
        >
          <li v-for="result in contactResults" :key="result.id">
            <button
              type="button"
              class="flex items-center w-full gap-2 px-3 py-2 text-sm text-start text-n-slate-12 hover:bg-n-alpha-2"
              @click="addContact(result)"
            >
              <Avatar :name="result.name" :size="20" rounded-full />
              <span class="truncate">{{ result.name }}</span>
              <span class="ml-auto text-xs truncate text-n-slate-10">
                {{ result.email || result.phone_number }}
              </span>
            </button>
          </li>
        </ul>
        <p v-if="isSearchingContacts" class="mt-1 text-xs text-n-slate-10">
          {{ t('FUNNEL.ASSOCIATIONS.SEARCHING') }}
        </p>
      </div>
    </section>

    <section class="flex flex-col gap-2">
      <span class="text-sm font-medium text-n-slate-12">
        {{ t('FUNNEL.ASSOCIATIONS.CONVERSATIONS') }}
      </span>
      <ul v-if="conversations.length" class="flex flex-col gap-1.5">
        <li
          v-for="conversation in conversations"
          :key="conversation.id"
          class="flex items-center gap-2 px-2 py-1.5 text-sm rounded-md bg-n-alpha-2"
        >
          <Icon icon="i-lucide-message-square" class="size-4 text-n-slate-11" />
          <router-link
            :to="conversationLink(conversation)"
            class="font-medium text-n-slate-12 hover:underline"
          >
            {{ `#${conversation.id}` }}
          </router-link>
          <span
            v-if="conversation.isPrimary"
            class="px-1.5 py-0.5 text-xs rounded bg-n-blue-3 text-n-blue-11"
          >
            {{ t('FUNNEL.ASSOCIATIONS.PRIMARY') }}
          </span>
          <div
            v-if="canEdit"
            class="flex items-center gap-1 ltr:ml-auto rtl:mr-auto"
          >
            <Button
              v-if="!conversation.isPrimary"
              variant="ghost"
              color="slate"
              size="xs"
              icon="i-lucide-star"
              :aria-label="t('FUNNEL.ASSOCIATIONS.MAKE_PRIMARY')"
              :disabled="isSaving"
              @click="promoteConversation(conversation.id)"
            />
            <Button
              variant="ghost"
              color="ruby"
              size="xs"
              icon="i-lucide-unlink"
              :aria-label="t('FUNNEL.ASSOCIATIONS.UNLINK')"
              :disabled="isSaving"
              @click="unlinkConversation(conversation.id)"
            />
          </div>
        </li>
      </ul>
      <p v-else class="text-xs text-n-slate-10">
        {{ t('FUNNEL.ASSOCIATIONS.NO_CONVERSATIONS') }}
      </p>
      <div v-if="canEdit" class="flex items-end gap-2">
        <Input
          v-model="conversationInput"
          type="number"
          class="flex-1"
          :placeholder="t('FUNNEL.ASSOCIATIONS.CONVERSATION_PLACEHOLDER')"
          :disabled="isSaving"
          @keydown.enter.prevent="linkConversation"
        />
        <Button
          variant="faded"
          color="slate"
          size="sm"
          :label="t('FUNNEL.ASSOCIATIONS.LINK')"
          :disabled="!conversationInput || isSaving"
          @click="linkConversation"
        />
      </div>
    </section>
  </div>
</template>
