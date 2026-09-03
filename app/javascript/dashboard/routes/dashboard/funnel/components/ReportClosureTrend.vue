<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  closures: { type: Array, default: () => [] },
});

const { t } = useI18n();

// Azul para ganho e rubi para perdido, e nao verde e vermelho. O par verde/vermelho e o classico
// que some para quem tem deuteranopia: medido, teal x rubi da deltaE 7.3, no piso do aceitavel;
// azul x rubi da 22.3 e ainda passa no contraste contra o fundo. O sentido vem do rotulo e do
// ponto colorido na legenda, nao da cor sozinha.
const WIDTH = 720;
const HEIGHT = 180;
const PADDING = { top: 12, right: 12, bottom: 24, left: 32 };

const hovered = ref(null);

const points = computed(() => props.closures ?? []);

const maxValue = computed(() =>
  Math.max(1, ...points.value.flatMap(row => [row.won, row.lost]))
);

const plotWidth = WIDTH - PADDING.left - PADDING.right;
const plotHeight = HEIGHT - PADDING.top - PADDING.bottom;

const xFor = index => {
  if (points.value.length <= 1) return PADDING.left + plotWidth / 2;

  return PADDING.left + (index / (points.value.length - 1)) * plotWidth;
};

const yFor = value =>
  PADDING.top + plotHeight - (value / maxValue.value) * plotHeight;

const pathFor = key =>
  points.value
    .map(
      (row, index) =>
        `${index === 0 ? 'M' : 'L'} ${xFor(index)} ${yFor(row[key])}`
    )
    .join(' ');

// Tres marcas no eixo: zero, meio e topo. Mais linhas numa altura de 180px viram grade densa e
// disputam atencao com os proprios dados.
const gridValues = computed(() => {
  const top = maxValue.value;
  return [0, Math.round(top / 2), top].filter(
    (value, index, all) => all.indexOf(value) === index
  );
});

const dateLabel = value => {
  const date = new Date(`${value}T00:00:00`);
  if (Number.isNaN(date.getTime())) return value;

  return `${String(date.getDate()).padStart(2, '0')}/${String(date.getMonth() + 1).padStart(2, '0')}`;
};

const tooltip = computed(() => {
  if (hovered.value === null) return null;

  const row = points.value[hovered.value];
  if (!row) return null;

  return {
    x: xFor(hovered.value),
    label: `${dateLabel(row.date)} · ${t('FUNNEL.REPORT.WON')} ${row.won} · ${t('FUNNEL.REPORT.LOST')} ${row.lost}`,
  };
});
</script>

<template>
  <div class="flex flex-col gap-2">
    <div class="flex items-center gap-4">
      <span class="flex items-center gap-1.5 text-xs text-n-slate-11">
        <span class="rounded-full size-2 bg-n-blue-9" />
        {{ t('FUNNEL.REPORT.WON') }}
      </span>
      <span class="flex items-center gap-1.5 text-xs text-n-slate-11">
        <span class="rounded-full size-2 bg-n-ruby-9" />
        {{ t('FUNNEL.REPORT.LOST') }}
      </span>
    </div>

    <svg
      :viewBox="`0 0 ${WIDTH} ${HEIGHT}`"
      class="w-full h-auto"
      role="img"
      :aria-label="t('FUNNEL.REPORT.CLOSURES')"
    >
      <g class="text-n-slate-6">
        <line
          v-for="value in gridValues"
          :key="`grid-${value}`"
          :x1="PADDING.left"
          :x2="WIDTH - PADDING.right"
          :y1="yFor(value)"
          :y2="yFor(value)"
          stroke="currentColor"
          stroke-width="1"
        />
      </g>

      <g class="text-n-slate-10" font-size="10" fill="currentColor">
        <text
          v-for="value in gridValues"
          :key="`label-${value}`"
          :x="PADDING.left - 6"
          :y="yFor(value) + 3"
          text-anchor="end"
        >
          {{ value }}
        </text>
      </g>

      <path
        :d="pathFor('won')"
        fill="none"
        stroke-width="2"
        stroke-linejoin="round"
        stroke-linecap="round"
        class="text-n-blue-9"
        stroke="currentColor"
      />
      <path
        :d="pathFor('lost')"
        fill="none"
        stroke-width="2"
        stroke-linejoin="round"
        stroke-linecap="round"
        class="text-n-ruby-9"
        stroke="currentColor"
      />

      <!-- Anel na cor da superficie onde as duas series se cruzam, para o ponto de cima nao
           parecer colado no de baixo. -->
      <g v-for="(row, index) in points" :key="`marks-${row.date}`">
        <circle
          :cx="xFor(index)"
          :cy="yFor(row.won)"
          r="4"
          class="text-n-blue-9"
          fill="currentColor"
          stroke="rgb(var(--color-n-solid-1, 255 255 255))"
          stroke-width="2"
        />
        <circle
          :cx="xFor(index)"
          :cy="yFor(row.lost)"
          r="4"
          class="text-n-ruby-9"
          fill="currentColor"
          stroke="rgb(var(--color-n-solid-1, 255 255 255))"
          stroke-width="2"
        />
      </g>

      <!-- Faixa invisivel por ponto: o alvo do mouse precisa ser maior que a marca de 8px. -->
      <rect
        v-for="(row, index) in points"
        :key="`hit-${row.date}`"
        :x="xFor(index) - plotWidth / Math.max(points.length, 1) / 2"
        :y="PADDING.top"
        :width="plotWidth / Math.max(points.length, 1)"
        :height="plotHeight"
        fill="transparent"
        @mouseenter="hovered = index"
        @mouseleave="hovered = null"
      />

      <line
        v-if="tooltip"
        :x1="tooltip.x"
        :x2="tooltip.x"
        :y1="PADDING.top"
        :y2="PADDING.top + plotHeight"
        class="text-n-slate-8"
        stroke="currentColor"
        stroke-width="1"
        stroke-dasharray="3 3"
      />

      <g class="text-n-slate-10" font-size="10" fill="currentColor">
        <text
          v-if="points.length"
          :x="PADDING.left"
          :y="HEIGHT - 6"
          text-anchor="start"
        >
          {{ dateLabel(points[0].date) }}
        </text>
        <text
          v-if="points.length > 1"
          :x="WIDTH - PADDING.right"
          :y="HEIGHT - 6"
          text-anchor="end"
        >
          {{ dateLabel(points[points.length - 1].date) }}
        </text>
      </g>
    </svg>

    <p v-if="tooltip" class="text-xs text-n-slate-11">{{ tooltip.label }}</p>
    <p v-else-if="!points.length" class="text-xs text-n-slate-10">
      {{ t('FUNNEL.REPORT.NO_CLOSURES') }}
    </p>
  </div>
</template>
