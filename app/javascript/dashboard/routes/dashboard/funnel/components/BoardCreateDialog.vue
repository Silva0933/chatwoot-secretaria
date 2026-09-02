<script setup>
import { computed, reactive, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import { BOARD_TEMPLATES } from 'dashboard/helper/funnelHelper';

defineProps({
  isLoading: { type: Boolean, default: false },
});

const emit = defineEmits(['create']);

const { t } = useI18n();

const dialogRef = ref(null);
const form = reactive({ name: '', description: '', template: 'clinic' });

const templateOptions = computed(() =>
  BOARD_TEMPLATES.map(template => ({
    value: template,
    label: t(`FUNNEL.BOARD_DIALOG.TEMPLATE.${template.toUpperCase()}`),
  }))
);

const isInvalid = computed(() => !form.name.trim());

const resetForm = () => {
  form.name = '';
  form.description = '';
  form.template = 'clinic';
};

const open = () => {
  resetForm();
  dialogRef.value?.open();
};

const close = () => dialogRef.value?.close();

const handleConfirm = () => {
  if (isInvalid.value) return;

  emit('create', {
    name: form.name.trim(),
    description: form.description.trim() || null,
    template: form.template,
  });
};

defineExpose({ open, close });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="md"
    :title="t('FUNNEL.BOARD_DIALOG.TITLE')"
    :confirm-button-label="t('FUNNEL.BOARD_DIALOG.CREATE')"
    :cancel-button-label="t('FUNNEL.BOARD_DIALOG.CANCEL')"
    :disable-confirm-button="isInvalid"
    :is-loading="isLoading"
    @confirm="handleConfirm"
    @close="resetForm"
  >
    <div class="flex flex-col gap-4">
      <Input
        v-model="form.name"
        :label="t('FUNNEL.BOARD_DIALOG.NAME_LABEL')"
        :placeholder="t('FUNNEL.BOARD_DIALOG.NAME_PLACEHOLDER')"
        :disabled="isLoading"
        autofocus
      />
      <TextArea
        v-model="form.description"
        :label="t('FUNNEL.BOARD_DIALOG.DESCRIPTION_LABEL')"
        :placeholder="t('FUNNEL.BOARD_DIALOG.DESCRIPTION_PLACEHOLDER')"
        :disabled="isLoading"
        :max-length="280"
        auto-height
      />
      <label class="flex flex-col gap-1">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('FUNNEL.BOARD_DIALOG.TEMPLATE_LABEL') }}
        </span>
        <Select
          v-model="form.template"
          :options="templateOptions"
          :disabled="isLoading"
          :aria-label="t('FUNNEL.BOARD_DIALOG.TEMPLATE_LABEL')"
        />
      </label>
    </div>
  </Dialog>
</template>
