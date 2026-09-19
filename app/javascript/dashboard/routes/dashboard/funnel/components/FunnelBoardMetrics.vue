<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

import Icon from 'dashboard/components-next/icon/Icon.vue';
import { boardMetrics, formatMoney } from 'dashboard/helper/funnelHelper';

const props = defineProps({
  tasks: { type: Array, default: () => [] },
  steps: { type: Array, default: () => [] },
  currency: { type: String, default: 'BRL' },
});

const { t, locale } = useI18n();

const metrics = computed(() => boardMetrics(props.tasks, props.steps));

const openValue = computed(() =>
  formatMoney(
    metrics.value.openValue,
    props.currency,
    locale.value.replace('_', '-')
  )
);

// Travessao e nao "0d" enquanto nada fechou: zero afirmaria que os cards fecham no mesmo dia
// em que nascem, quando o que se sabe e que nenhum fechou ainda.
const cycleLabel = computed(() =>
  metrics.value.cycleDays === null
    ? '—'
    : t('FUNNEL.METRICS.DAYS', { count: metrics.value.cycleDays })
);

// O avanco e uma fracao e nao uma media ponderada: "2 de 11 sairam da primeira etapa" e uma
// frase que se confere olhando as colunas. Um indice ponderado por probabilidade seria mais
// preciso e ninguem saberia dizer de onde veio.
const advance = computed(() => {
  const { advanced, opportunities } = metrics.value;
  if (!opportunities) return null;

  return {
    advanced,
    total: opportunities,
    percent: Math.round((advanced / opportunities) * 100),
  };
});
</script>

<template>
  <div
    class="flex items-stretch gap-6 px-4 py-3 mx-6 mb-3 border rounded-xl border-n-weak bg-n-solid-1"
  >
    <div class="flex flex-col gap-0.5">
      <span class="text-xs font-medium tracking-wide uppercase text-n-slate-10">
        {{ t('FUNNEL.METRICS.OPEN_VALUE') }}
      </span>
      <span class="text-lg font-semibold tabular-nums text-n-slate-12">
        {{ openValue }}
      </span>
    </div>

    <div class="w-px bg-n-weak" />

    <div class="flex flex-col gap-0.5">
      <span class="text-xs font-medium tracking-wide uppercase text-n-slate-10">
        {{ t('FUNNEL.METRICS.OPPORTUNITIES') }}
      </span>
      <span class="text-lg font-semibold tabular-nums text-n-slate-12">
        {{ metrics.opportunities }}
      </span>
    </div>

    <div class="w-px bg-n-weak" />

    <div class="flex flex-col gap-0.5">
      <span class="text-xs font-medium tracking-wide uppercase text-n-slate-10">
        {{ t('FUNNEL.METRICS.CYCLE') }}
      </span>
      <span class="text-lg font-semibold tabular-nums text-n-slate-12">
        {{ cycleLabel }}
      </span>
    </div>

    <div class="w-px bg-n-weak" />

    <!-- Em ambar sempre, mesmo em zero: e a unica metrica da faixa que pede acao, e a cor e o
         que faz o olho passar por ela antes das outras tres. -->
    <div class="flex flex-col gap-0.5">
      <span
        class="flex items-center gap-1 text-xs font-medium tracking-wide uppercase"
        :class="metrics.waiting ? 'text-n-amber-11' : 'text-n-slate-10'"
      >
        <Icon icon="i-lucide-clock" class="size-3" />
        {{ t('FUNNEL.METRICS.WAITING') }}
      </span>
      <span
        class="text-lg font-semibold tabular-nums"
        :class="metrics.waiting ? 'text-n-amber-11' : 'text-n-slate-12'"
      >
        {{ metrics.waiting }}
      </span>
    </div>

    <div class="grow" />

    <div
      v-if="advance"
      class="flex flex-col justify-center gap-1.5 w-64 shrink-0"
    >
      <div class="flex items-baseline justify-between">
        <span
          class="text-xs font-medium tracking-wide uppercase text-n-slate-10"
        >
          {{ t('FUNNEL.METRICS.ADVANCE') }}
        </span>
        <span class="text-xs tabular-nums text-n-slate-10">
          {{
            t('FUNNEL.METRICS.ADVANCE_OF', {
              advanced: advance.advanced,
              total: advance.total,
            })
          }}
        </span>
      </div>
      <div
        class="flex h-1.5 gap-0.5 overflow-hidden rounded-full"
        role="img"
        :aria-label="
          t('FUNNEL.METRICS.ADVANCE_OF', {
            advanced: advance.advanced,
            total: advance.total,
          })
        "
      >
        <div
          class="bg-n-blue-9"
          :style="{ width: `${100 - advance.percent}%` }"
        />
        <div class="bg-n-teal-9" :style="{ width: `${advance.percent}%` }" />
      </div>
    </div>
  </div>
</template>
