<script setup>
import { computed, ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';

import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useFunnelStore } from 'dashboard/stores/funnel';
import { formatMoney } from 'dashboard/helper/funnelHelper';
import FunnelReportsApi from 'dashboard/api/funnel/reports';

import Button from 'dashboard/components-next/button/Button.vue';
import Select from 'dashboard/components-next/select/Select.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import BackButton from 'dashboard/components/widgets/BackButton.vue';
import ReportClosureTrend from '../components/ReportClosureTrend.vue';
import ReportStageBars from '../components/ReportStageBars.vue';

const { t, locale } = useI18n();
const route = useRoute();
const { accountId, currentAccount } = useAccount();
const funnelStore = useFunnelStore();

const PERIODS = [7, 30, 90];
const periodDays = ref(30);

const isModuleEnabled = computed(() =>
  Boolean(currentAccount.value?.settings?.funnel_kanban_enabled)
);

const boardId = computed(() => Number(route.query.board) || null);
const report = computed(() => funnelStore.report);

// Uma serie com so zeros nao e uma serie: o grafico desenharia o eixo e nenhuma linha. Vale
// tambem para o periodo que devolve dias, mas todos sem fechamento.
const hasClosures = computed(() =>
  (report.value?.closures ?? []).some(
    day => (day.won ?? 0) + (day.lost ?? 0) > 0
  )
);
const isFetching = computed(() => funnelStore.getUIFlags.fetchingReport);
const board = computed(() =>
  funnelStore.getBoards.find(item => item.id === boardId.value)
);

const periodOptions = computed(() =>
  PERIODS.map(days => ({
    value: days,
    label: t('FUNNEL.REPORT.LAST_DAYS', { days }),
  }))
);

const since = computed(() =>
  new Date(Date.now() - periodDays.value * 86400000).toISOString()
);

const currency = computed(() => report.value?.range?.currency ?? 'BRL');
const money = value =>
  formatMoney(value, currency.value, locale.value.replace('_', '-'));

// Numero grande e sem grafico: sao valores unicos, e enfiar cada um num mini-grafico daria
// decoracao no lugar da leitura.
const tiles = computed(() => {
  const totals = report.value?.totals;
  if (!totals) return [];

  return [
    { key: 'created', value: totals.created },
    { key: 'won', value: totals.won, tone: 'text-n-blue-11' },
    { key: 'lost', value: totals.lost, tone: 'text-n-ruby-11' },
    {
      key: 'win_rate',
      value: totals.winRate === null ? '—' : `${totals.winRate}%`,
    },
    { key: 'open_value', value: money(totals.openValue) },
    { key: 'weighted_value', value: money(totals.weightedValue) },
  ];
});

const stepName = id =>
  report.value?.steps?.find(step => step.id === id)?.name ?? `#${id}`;

const load = async () => {
  if (!isModuleEnabled.value || !boardId.value) return;

  try {
    if (!funnelStore.getBoards.length) await funnelStore.fetchBoards();
    await funnelStore.fetchReport({
      boardId: boardId.value,
      since: since.value,
    });
  } catch (error) {
    useAlert(error.message);
  }
};

const exportCsv = () => {
  window.open(
    FunnelReportsApi.exportUrl(boardId.value, { since: since.value }),
    '_blank',
    'noopener'
  );
};

watch([boardId, periodDays, isModuleEnabled], load, { immediate: true });
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <header class="flex items-center justify-between gap-4 px-6 h-20 shrink-0">
      <div class="flex items-center gap-3">
        <BackButton
          :back-url="`/app/accounts/${accountId}/funnel?board=${boardId}`"
        />
        <h1 class="text-xl font-medium truncate text-n-slate-12">
          {{ t('FUNNEL.REPORT.TITLE') }}
        </h1>
        <span v-if="board" class="text-sm text-n-slate-11">{{
          board.name
        }}</span>
      </div>

      <div class="flex items-center gap-2">
        <Select
          v-model="periodDays"
          :options="periodOptions"
          class="w-40"
          :aria-label="t('FUNNEL.REPORT.PERIOD')"
        />
        <Button
          variant="faded"
          color="slate"
          size="sm"
          icon="i-lucide-download"
          :label="t('FUNNEL.REPORT.EXPORT')"
          :disabled="!report"
          @click="exportCsv"
        />
      </div>
    </header>

    <div
      v-if="isFetching && !report"
      class="flex items-center justify-center grow"
    >
      <Spinner />
    </div>

    <div
      v-else-if="!boardId"
      class="flex items-center justify-center px-6 text-sm text-center grow text-n-slate-11"
    >
      {{ t('FUNNEL.REPORT.PICK_BOARD') }}
    </div>

    <div
      v-else-if="report"
      class="flex flex-col gap-6 px-6 pb-8 overflow-y-auto"
    >
      <div class="grid grid-cols-2 gap-3 lg:grid-cols-6">
        <div
          v-for="tile in tiles"
          :key="tile.key"
          class="flex flex-col gap-1 p-3 border rounded-lg border-n-weak bg-n-solid-1"
        >
          <span class="text-xs text-n-slate-11">
            {{ t(`FUNNEL.REPORT.TILES.${tile.key.toUpperCase()}`) }}
          </span>
          <span
            class="text-xl font-semibold"
            :class="tile.tone || 'text-n-slate-12'"
          >
            {{ tile.value }}
          </span>
        </div>
      </div>

      <section
        class="flex flex-col gap-3 p-4 border rounded-lg border-n-weak bg-n-solid-1"
      >
        <div class="flex items-baseline justify-between gap-2">
          <h2 class="text-sm font-medium text-n-slate-12">
            {{ t('FUNNEL.REPORT.BY_STAGE') }}
          </h2>
          <span class="text-xs text-n-slate-10">
            {{ t('FUNNEL.REPORT.BY_STAGE_LEGEND') }}
          </span>
        </div>
        <ReportStageBars :steps="report.steps" />
      </section>

      <!-- Some quando nao ha fechamento no periodo, em vez de reservar 250px para um eixo sem
           serie nenhuma. Um funil que ainda nao fechou nada e o caso normal de quem acabou de
           comecar, e o espaco vazio empurrava o resto do relatorio para fora da tela. -->
      <section
        v-if="hasClosures"
        class="flex flex-col gap-3 p-4 border rounded-lg border-n-weak bg-n-solid-1"
      >
        <h2 class="text-sm font-medium text-n-slate-12">
          {{ t('FUNNEL.REPORT.CLOSURES') }}
        </h2>
        <ReportClosureTrend :closures="report.closures" />
      </section>

      <div class="grid grid-cols-1 gap-4 lg:grid-cols-2">
        <section
          class="flex flex-col gap-3 p-4 border rounded-lg border-n-weak bg-n-solid-1"
        >
          <h2 class="text-sm font-medium text-n-slate-12">
            {{ t('FUNNEL.REPORT.CONVERSION') }}
          </h2>
          <table v-if="report.transitions.length" class="w-full text-sm">
            <tbody>
              <tr
                v-for="row in report.transitions"
                :key="`${row.fromStepId}-${row.toStepId}`"
                class="border-b border-n-weak last:border-0"
              >
                <td class="py-1.5 text-n-slate-11">
                  {{
                    `${stepName(row.fromStepId)} → ${stepName(row.toStepId)}`
                  }}
                </td>
                <td class="py-1.5 font-medium text-right text-n-slate-12">
                  {{ row.count }}
                </td>
              </tr>
            </tbody>
          </table>
          <p v-else class="text-xs text-n-slate-10">
            {{ t('FUNNEL.REPORT.NO_CONVERSION') }}
          </p>
        </section>

        <section
          class="flex flex-col gap-3 p-4 border rounded-lg border-n-weak bg-n-solid-1"
        >
          <h2 class="text-sm font-medium text-n-slate-12">
            {{ t('FUNNEL.REPORT.AGENTS') }}
          </h2>
          <table v-if="report.agents.length" class="w-full text-sm">
            <thead>
              <tr class="text-xs text-n-slate-10">
                <th class="font-normal text-start">
                  {{ t('FUNNEL.REPORT.AGENT') }}
                </th>
                <th class="font-normal text-end">
                  {{ t('FUNNEL.REPORT.WON') }}
                </th>
                <th class="font-normal text-end">
                  {{ t('FUNNEL.REPORT.LOST') }}
                </th>
                <th class="font-normal text-end">
                  {{ t('FUNNEL.REPORT.OPEN') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="row in report.agents"
                :key="row.userId"
                class="border-b border-n-weak last:border-0"
              >
                <td class="py-1.5 truncate text-n-slate-12">{{ row.name }}</td>
                <td class="py-1.5 text-end text-n-slate-12">{{ row.won }}</td>
                <td class="py-1.5 text-end text-n-slate-11">{{ row.lost }}</td>
                <td class="py-1.5 text-end text-n-slate-11">{{ row.open }}</td>
              </tr>
            </tbody>
          </table>
          <p v-else class="text-xs text-n-slate-10">
            {{ t('FUNNEL.REPORT.NO_AGENTS') }}
          </p>
        </section>
      </div>

      <section
        v-if="report.stalled.length"
        class="flex flex-col gap-3 p-4 border rounded-lg border-n-weak bg-n-solid-1"
      >
        <h2 class="text-sm font-medium text-n-slate-12">
          {{ t('FUNNEL.REPORT.STALLED') }}
        </h2>
        <ul class="flex flex-col gap-1.5">
          <li
            v-for="task in report.stalled"
            :key="task.id"
            class="flex items-center justify-between gap-3 text-sm"
          >
            <span class="truncate text-n-slate-12">{{ task.title }}</span>
            <span class="text-xs shrink-0 text-n-slate-10">
              {{
                `${task.stepName} · ${t('FUNNEL.REPORT.DAYS', { days: task.days })}`
              }}
            </span>
          </li>
        </ul>
      </section>
    </div>
  </section>
</template>
