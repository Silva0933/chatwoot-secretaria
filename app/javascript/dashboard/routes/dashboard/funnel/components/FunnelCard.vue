<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { OnClickOutside } from '@vueuse/components';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import ChannelIcon from 'dashboard/components-next/icon/ChannelIcon.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import FunnelCardMenu from './FunnelCardMenu.vue';
import {
  waitingState,
  stageAge,
  dueState,
  formatMoney,
  DUE_STATES,
  URGENCY_META,
  WAITING_LEVELS,
} from 'dashboard/helper/funnelHelper';
import { useFunnelStore } from 'dashboard/stores/funnel';

const props = defineProps({
  task: { type: Object, required: true },
  steps: { type: Array, default: () => [] },
  canArchive: { type: Boolean, default: false },
});

const emit = defineEmits([
  'open',
  'openConversation',
  'move',
  'assign',
  'setUrgency',
  'archive',
]);

const { t } = useI18n();
const funnelStore = useFunnelStore();

const showMenu = ref(false);

// O relogio e a urgencia falam a mesma lingua: ambar quando comeca a doer, rubi quando ja doeu.
// Sao as duas unicas cores do card, e nenhuma das duas aparece sozinha — sempre com icone.
const WAITING_CLASSES = {
  [WAITING_LEVELS.CALM]: 'bg-n-alpha-2 text-n-slate-11',
  [WAITING_LEVELS.WARN]: 'bg-n-amber-3 text-n-amber-11',
  [WAITING_LEVELS.ALERT]: 'bg-n-ruby-3 text-n-ruby-11',
};

const URGENCY_CLASSES = {
  amber: 'text-n-amber-11',
  ruby: 'text-n-ruby-11',
};

// A borda a esquerda e o que faz o card destoar da coluna sem gritar: dois pixels na lateral,
// nao um fundo colorido. Um quadro em que todo card tem fundo proprio vira lista de alarmes.
const BORDER_CLASSES = {
  amber:
    'ltr:border-l-2 rtl:border-r-2 border-l-n-amber-9 rtl:border-r-n-amber-9',
  ruby: 'ltr:border-l-2 rtl:border-r-2 border-l-n-ruby-9 rtl:border-r-n-ruby-9',
};

// O prazo so aparece quando pede acao: atrasado ou vencendo hoje. Um card que vence em doze
// dias nao muda o que alguem faz agora, e um selo de data em todo card devolveria exatamente o
// ruido que o redesenho tirou. As outras datas continuam no dialogo do card.
const DUE_CLASSES = {
  [DUE_STATES.OVERDUE]: 'bg-n-ruby-3 text-n-ruby-11',
  [DUE_STATES.TODAY]: 'bg-n-amber-3 text-n-amber-11',
};

const MAX_VISIBLE_LABELS = 3;

const contact = computed(() => (props.task.contacts ?? [])[0] ?? null);

const labels = computed(() => props.task.labels ?? []);
const visibleLabels = computed(() => labels.value.slice(0, MAX_VISIBLE_LABELS));
const hiddenLabelCount = computed(
  () => labels.value.length - visibleLabels.value.length
);

const due = computed(() => {
  const state = dueState(props.task.dueAt);
  if (state !== DUE_STATES.OVERDUE && state !== DUE_STATES.TODAY) return null;

  return {
    classes: DUE_CLASSES[state],
    label:
      state === DUE_STATES.OVERDUE
        ? t('FUNNEL.CARD.OVERDUE')
        : t('FUNNEL.CARD.TODAY'),
  };
});

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

// Conversa de grupo do WhatsApp chega com o id do grupo como titulo: dezoito digitos que nao
// dizem nada a ninguem. Havendo contato, ele vira o titulo. O id nao se perde — continua sendo o
// titulo do card quando aberto.
const GROUP_ID_PATTERN = /^\d{12,}$/;

const title = computed(() => {
  const raw = props.task.title?.trim();
  if (!raw) return t('FUNNEL.CARD.NO_TITLE');
  if (GROUP_ID_PATTERN.test(raw) && contact.value?.name) {
    return contact.value.name;
  }

  return raw;
});

// Quanto vale a oportunidade, na moeda do quadro. Vazio quando nao ha valor: "R$ 0" afirmaria
// que nao vale nada, e o que se sabe e que ninguem precificou.
const value = computed(() => {
  const amount = Number(props.task.value);
  if (!Number.isFinite(amount) || !amount) return '';

  return formatMoney(amount, funnelStore.getActiveBoard?.currency || 'BRL');
});

// A ultima coisa que o cliente disse, em duas linhas. O backend ja escolhe a mensagem e ja corta
// o comprimento; card sem conversa cai para a descricao, que e o unico texto que ele tem.
const excerpt = computed(() => props.task.excerpt?.trim() || '');

const assignees = computed(() => props.task.assignees ?? []);
const owner = computed(() => assignees.value[0] ?? null);
const extraAssignees = computed(() => assignees.value.length - 1);

const waiting = computed(() => {
  const state = waitingState(props.task.waitingSince);
  if (!state) return null;

  return { ...state, classes: WAITING_CLASSES[state.level] };
});

// So em etapa aberta. Em Ganho e Perdido o atendimento acabou, e "ha 12 dias nesta etapa" ali
// mede o tempo desde o fechamento: um numero que cresce para sempre e nao pede acao nenhuma.
const stage = computed(() => {
  if (props.task.stepStageType !== 'open') return null;

  return stageAge(props.task.stepChangedAt);
});

const urgency = computed(() => {
  const meta = URGENCY_META[props.task.priority];
  if (!meta) return null;

  return {
    ...meta,
    classes: URGENCY_CLASSES[meta.tone],
    border: BORDER_CLASSES[meta.tone],
    label: t(`FUNNEL.URGENCY.${props.task.priority.toUpperCase()}`),
  };
});

const conversations = computed(() => props.task.conversations ?? []);

// A conversa que o card abre: a principal, ou a primeira quando nenhuma foi promovida.
const primaryConversation = computed(
  () =>
    conversations.value.find(conversation => conversation.isPrimary) ??
    conversations.value[0] ??
    null
);

// O corpo do card leva para a conversa, que e o que o agente quer na maioria das vezes; as
// opcoes ficam no menu. Sem conversa vinculada nao ha para onde navegar, entao ali o corpo
// volta a abrir o card.
const activate = () => {
  if (primaryConversation.value) {
    emit('openConversation', primaryConversation.value);
    return;
  }

  emit('open', props.task);
};

const openConversation = () => {
  if (primaryConversation.value)
    emit('openConversation', primaryConversation.value);
};

const openLabel = computed(() =>
  primaryConversation.value
    ? t('FUNNEL.CARD.OPEN_CONVERSATION')
    : t('FUNNEL.CARD.OPEN')
);
</script>

<template>
  <div
    class="relative flex flex-col gap-2 p-3 border rounded-lg cursor-pointer select-none group bg-n-solid-1 border-n-weak hover:border-n-slate-6 hover:shadow-sm"
    :class="urgency?.border"
    role="button"
    tabindex="0"
    :aria-label="openLabel"
    @click="activate"
    @keydown.enter.prevent="activate"
    @keydown.space.prevent="activate"
  >
    <!-- 1. quem e e quanto vale.
         A linha abre espaco a direita no hover: o botao de opcoes flutua sobre este canto e sem
         isso cobriria justamente o valor, que e a metade mais importante da linha. -->
    <div
      class="flex items-start gap-2 transition-[padding] group-hover:ltr:pr-7 group-hover:rtl:pl-7"
    >
      <span class="text-sm font-semibold truncate grow text-n-slate-12">
        {{ title }}
      </span>
      <span
        v-if="value"
        class="text-sm font-semibold shrink-0 tabular-nums text-n-slate-12"
      >
        {{ value }}
      </span>
    </div>

    <!-- 2. o que o cliente disse por ultimo -->
    <p v-if="excerpt" class="text-xs text-n-slate-11 line-clamp-2">
      {{ excerpt }}
    </p>

    <!-- Etiquetas, quando ha. Ficam acima do divisor porque descrevem o card, nao o estado do
         atendimento — que e o que a linha de baixo responde. -->
    <div v-if="labels.length" class="flex flex-wrap gap-1">
      <span
        v-for="label in visibleLabels"
        :key="label.id"
        class="flex items-center gap-1 px-1.5 py-0.5 text-xs rounded bg-n-alpha-2 text-n-slate-11"
      >
        <span
          class="rounded-sm size-2 shrink-0"
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

    <div class="h-px bg-n-weak" />

    <!-- 3, 4 e 5: quem atende, ha quanto tempo o cliente espera, quao urgente e -->
    <div class="flex items-center gap-1.5">
      <Avatar
        v-if="owner"
        :name="owner.name"
        :src="owner.avatarUrl"
        :size="20"
        rounded-full
        class="shrink-0"
      />
      <!-- Card sem responsavel nao fica sem a linha: "ninguem esta atendendo" e uma resposta, e
           e a que mais pede acao. O tracejado diz isso sem precisar de cor. -->
      <span
        v-else
        class="flex items-center justify-center border border-dashed rounded-full size-5 shrink-0 border-n-strong text-n-slate-10"
      >
        <Icon icon="i-lucide-user-round" class="size-3" />
      </span>
      <span
        class="text-xs truncate grow"
        :class="owner ? 'text-n-slate-11' : 'text-n-slate-10'"
      >
        {{ owner ? owner.name : t('FUNNEL.CARD.UNASSIGNED') }}
      </span>
      <span v-if="extraAssignees > 0" class="text-xs shrink-0 text-n-slate-10">
        {{ `+${extraAssignees}` }}
      </span>

      <!-- Canal e numero de conversas em cinza, sem fundo: sao procedencia, nao alarme. O que
           pede acao nesta linha e o que vem depois deles, colorido. -->
      <span
        v-if="channelInbox"
        class="flex items-center shrink-0 text-n-slate-10"
        :title="channelInbox.name"
      >
        <ChannelIcon :inbox="channelInbox" use-brand-icon class="size-3.5" />
      </span>

      <span
        v-if="conversations.length"
        class="flex items-center gap-1 text-xs shrink-0 text-n-slate-10"
        :title="t('FUNNEL.ASSOCIATIONS.CONVERSATIONS')"
      >
        <Icon icon="i-lucide-message-square" class="size-3" />
        {{ conversations.length }}
      </span>

      <!-- Tempo parado nesta etapa, na mesma familia do canal e do contador: cinza e sem fundo.
           E contexto para ler a coluna, nao alarme — quem alarma e o vencimento e o relogio do
           cliente, os dois logo depois deste. -->
      <span
        v-if="stage"
        class="flex items-center gap-1 text-xs shrink-0 text-n-slate-10 tabular-nums"
        :title="t('FUNNEL.CARD.STAGE_AGE')"
      >
        <Icon icon="i-lucide-hourglass" class="size-3" />
        {{ stage.label }}
      </span>

      <span
        v-if="due"
        class="flex items-center gap-1 px-1.5 py-0.5 text-xs font-medium rounded shrink-0"
        :class="due.classes"
      >
        <Icon icon="i-lucide-alert-circle" class="size-3" />
        {{ due.label }}
      </span>

      <span
        v-if="waiting"
        class="flex items-center gap-1 px-1.5 py-0.5 rounded shrink-0"
        :class="waiting.classes"
        :title="t('FUNNEL.CARD.WAITING_SINCE')"
      >
        <Icon icon="i-lucide-clock" class="size-3" />
        <span class="text-xs font-medium tabular-nums">{{
          waiting.label
        }}</span>
      </span>

      <span
        v-if="urgency"
        class="flex items-center shrink-0"
        :class="urgency.classes"
        :title="urgency.label"
        :aria-label="urgency.label"
      >
        <Icon :icon="urgency.icon" class="size-4" />
      </span>
    </div>

    <!-- Repouso mostra informacao, hover mostra acao: e isso que abriu espaco para as cinco
         linhas acima. O stop impede que o clique chegue ao corpo, que navega para a conversa. -->
    <OnClickOutside
      class="absolute ltr:right-1.5 rtl:left-1.5 top-1.5"
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
        :aria-label="t('FUNNEL.CARD.MENU.LABEL')"
        :aria-expanded="showMenu"
        @click.stop="showMenu = !showMenu"
        @keydown.stop
      >
        <Icon icon="i-lucide-ellipsis-vertical" class="size-3.5" />
      </button>

      <FunnelCardMenu
        v-if="showMenu"
        :task="task"
        :steps="steps"
        :has-conversation="Boolean(primaryConversation)"
        :can-archive="canArchive"
        @click.stop
        @keydown.stop
        @edit="$emit('open', task)"
        @open-conversation="openConversation"
        @move="$emit('move', $event)"
        @assign="$emit('assign', $event)"
        @set-urgency="$emit('setUrgency', $event)"
        @archive="$emit('archive', task)"
        @close="showMenu = false"
      />
    </OnClickOutside>
  </div>
</template>
