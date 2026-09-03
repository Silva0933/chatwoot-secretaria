<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  steps: { type: Array, default: () => [] },
});

const { t } = useI18n();

// Barra em HTML e nao em SVG: sao poucas barras horizontais, e uma div com largura percentual
// acompanha o container sozinha, sem viewBox nem calculo de escala.
//
// Uma cor so para as barras, e nao a cor de cada etapa. A barra codifica magnitude, que e um
// trabalho de escala sequencial; a identidade da etapa vem do nome ao lado e de um ponto na cor
// que o usuario escolheu. Usar a cor da etapa na barra tambem deixaria o grafico refem de
// escolhas que ninguem validou contra o fundo.
const maxCount = computed(() =>
  Math.max(1, ...props.steps.map(step => step.count ?? 0))
);

const rows = computed(() =>
  props.steps.map(step => ({
    ...step,
    // Minimo de 2% para a etapa com um card nao sumir: barra invisivel e lida como zero.
    width: step.count ? Math.max((step.count / maxCount.value) * 100, 2) : 0,
  }))
);

const medianLabel = seconds => {
  if (!seconds) return '—';

  const days = seconds / 86400;
  if (days >= 1) return `${Math.round(days)}d`;

  return `${Math.max(Math.round(seconds / 3600), 1)}h`;
};
</script>

<template>
  <div class="flex flex-col gap-3">
    <div
      v-for="row in rows"
      :key="row.id"
      class="flex items-center gap-3"
      :title="
        t('FUNNEL.REPORT.STAGE_TOOLTIP', {
          count: row.count,
          stalled: row.stalledCount,
        })
      "
    >
      <div class="flex items-center w-40 gap-2 shrink-0">
        <span
          class="rounded-full size-2 shrink-0"
          :style="{ backgroundColor: row.color }"
        />
        <span class="text-sm truncate text-n-slate-12">{{ row.name }}</span>
      </div>

      <div class="relative flex-1 h-6 rounded bg-n-alpha-1">
        <div
          class="h-6 rounded bg-n-blue-9"
          :style="{ width: `${row.width}%` }"
        />
      </div>

      <span class="w-10 text-sm font-medium text-right text-n-slate-12">
        {{ row.count }}
      </span>
      <span class="w-12 text-xs text-right text-n-slate-10">
        {{ medianLabel(row.medianAgeSeconds) }}
      </span>
      <span
        class="w-10 text-xs text-right"
        :class="row.stalledCount ? 'text-n-amber-11' : 'text-n-slate-10'"
      >
        {{ row.stalledCount || '—' }}
      </span>
    </div>
  </div>
</template>
