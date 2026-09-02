/**
 * Helpers do modulo Funnel (quadro Kanban).
 *
 * O rank chega da API como string e nao como numero: a coluna e decimal(30,15) e
 * `JSON.parse` transformaria "65536.000000000000001" num float, perdendo justamente as casas
 * que separam dois cards vizinhos. Toda comparacao aqui e feita sobre a string.
 */

const parseDecimal = value => {
  const raw = String(value ?? '0').trim();
  const negative = raw.startsWith('-');
  const [integer = '0', fraction = ''] = raw.replace(/^[+-]/, '').split('.');

  return {
    negative,
    integer: integer.replace(/^0+(?=\d)/, '') || '0',
    fraction: fraction.replace(/0+$/, ''),
  };
};

const isZero = decimal => decimal.integer === '0' && decimal.fraction === '';

const compareMagnitude = (a, b) => {
  if (a.integer.length !== b.integer.length) {
    return a.integer.length < b.integer.length ? -1 : 1;
  }
  if (a.integer !== b.integer) return a.integer < b.integer ? -1 : 1;

  const length = Math.max(a.fraction.length, b.fraction.length);
  const fractionA = a.fraction.padEnd(length, '0');
  const fractionB = b.fraction.padEnd(length, '0');
  if (fractionA === fractionB) return 0;

  return fractionA < fractionB ? -1 : 1;
};

/**
 * Comparador de ranks. Ranks podem ser negativos: `Funnel::Ranking.prepend_before` subtrai um
 * STEP inteiro do primeiro card da etapa.
 */
export const compareRank = (a, b) => {
  const left = parseDecimal(a);
  const right = parseDecimal(b);

  const leftIsZero = isZero(left);
  const rightIsZero = isZero(right);
  if (leftIsZero && rightIsZero) return 0;

  if (left.negative !== right.negative) {
    if (leftIsZero) return right.negative ? 1 : -1;
    if (rightIsZero) return left.negative ? -1 : 1;
    return left.negative ? -1 : 1;
  }

  const magnitude = compareMagnitude(left, right);
  return left.negative ? -magnitude : magnitude;
};

export const sortByRank = (items = []) =>
  [...items].sort((a, b) => compareRank(a.rank, b.rank));

export const SORT_OPTIONS = [
  'position',
  'priority',
  'due',
  'created',
  'updated',
  'title',
];

export const EMPTY_FILTERS = Object.freeze({
  search: '',
  assigneeId: null,
  inboxId: null,
  priority: null,
  labelId: null,
});

export const hasActiveFilters = filters =>
  Object.entries(EMPTY_FILTERS).some(
    ([key, empty]) => (filters?.[key] ?? empty) !== empty
  );

const matchesSearch = (task, term) => {
  if (!term) return true;

  const needle = term.trim().toLowerCase();
  if (!needle) return true;

  return [task.title, task.description]
    .filter(Boolean)
    .some(field => field.toLowerCase().includes(needle));
};

/**
 * Filtro do quadro, aplicado no cliente.
 *
 * O quadro ja carrega todos os cards ativos de uma vez, entao filtrar aqui responde na hora e
 * mantem os contadores das colunas exatos sem uma segunda consulta. O limite dessa escolha e o
 * tamanho do quadro: passando de alguns milhares de cards ativos, o filtro precisa descer para
 * o servidor junto com paginacao.
 */
export const filterTasks = (tasks = [], filters = EMPTY_FILTERS) =>
  tasks.filter(task => {
    if (!matchesSearch(task, filters.search)) return false;

    if (
      filters.assigneeId &&
      !(task.assignees ?? []).some(user => user.id === filters.assigneeId)
    ) {
      return false;
    }

    if (filters.inboxId && task.channel?.inboxId !== filters.inboxId) {
      return false;
    }

    if (filters.priority && task.priority !== filters.priority) return false;

    if (
      filters.labelId &&
      !(task.labels ?? []).some(label => label.id === filters.labelId)
    ) {
      return false;
    }

    return true;
  });

const PRIORITY_WEIGHT = { urgent: 4, high: 3, medium: 2, low: 1 };

const byDate = (left, right, key) => {
  // Card sem a data vai para o fim: uma data ausente nao e "muito antiga", e ordenar como se
  // fosse jogaria os cards sem prazo para o topo de "vence primeiro".
  const a = left[key] ? new Date(left[key]).getTime() : Infinity;
  const b = right[key] ? new Date(right[key]).getTime() : Infinity;
  return a - b;
};

export const sortTasks = (tasks = [], sortBy = 'position') => {
  const copy = [...tasks];

  switch (sortBy) {
    case 'priority':
      // Sem prioridade vai por ultimo, e o desempate e a posicao, para a ordem nao dancar entre
      // dois cards igualmente urgentes a cada redesenho.
      return copy.sort(
        (left, right) =>
          (PRIORITY_WEIGHT[right.priority] ?? 0) -
            (PRIORITY_WEIGHT[left.priority] ?? 0) ||
          compareRank(left.rank, right.rank)
      );
    case 'due':
      return copy.sort(
        (left, right) =>
          byDate(left, right, 'dueAt') || compareRank(left.rank, right.rank)
      );
    case 'created':
      return copy.sort((left, right) => byDate(right, left, 'createdAt'));
    case 'updated':
      return copy.sort((left, right) => byDate(right, left, 'updatedAt'));
    case 'title':
      return copy.sort((left, right) =>
        (left.title ?? '').localeCompare(right.title ?? '')
      );
    default:
      return sortByRank(copy);
  }
};

/**
 * Distribui os cards nas etapas do quadro, cada lista ja ordenada por rank.
 * Cards cuja etapa nao existe mais na resposta ficam de fora, em vez de sumir numa coluna
 * fantasma.
 */
export const groupTasksByStep = (
  steps = [],
  tasks = [],
  sortBy = 'position'
) => {
  const grouped = Object.fromEntries(steps.map(step => [step.id, []]));

  tasks.forEach(task => {
    if (grouped[task.funnelStepId]) grouped[task.funnelStepId].push(task);
  });

  Object.keys(grouped).forEach(stepId => {
    grouped[stepId] = sortTasks(grouped[stepId], sortBy);
  });

  return grouped;
};

/**
 * Traduz a posicao final de um card na coluna nos ids dos vizinhos que a API espera.
 * `orderedTasks` e a coluna de destino ja com o card na posicao nova.
 */
export const neighboursAt = (orderedTasks, taskId) => {
  const ordered = orderedTasks ?? [];
  const index = ordered.findIndex(task => task.id === taskId);
  if (index === -1) return { afterId: null, beforeId: null };

  return {
    afterId: ordered[index - 1]?.id ?? null,
    beforeId: ordered[index + 1]?.id ?? null,
  };
};

const MINUTE = 60 * 1000;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;

/**
 * Ha quanto tempo o card esta parado na etapa, no formato curto do quadro: 55m, 3h, 12d.
 *
 * Curto de proposito. E um sinal de triagem lido de relance em dezenas de cards ao mesmo tempo,
 * nao uma data — "ha 3 dias" ocuparia a linha inteira e diria a mesma coisa.
 */
export const timeInStep = (stepChangedAt, now = Date.now()) => {
  if (!stepChangedAt) return '';

  const since = new Date(stepChangedAt).getTime();
  if (Number.isNaN(since)) return '';

  const elapsed = Math.max(now - since, 0);
  if (elapsed < HOUR) return `${Math.max(Math.floor(elapsed / MINUTE), 1)}m`;
  if (elapsed < DAY) return `${Math.floor(elapsed / HOUR)}h`;

  return `${Math.floor(elapsed / DAY)}d`;
};

export const DUE_STATES = {
  OVERDUE: 'overdue',
  TODAY: 'today',
  TOMORROW: 'tomorrow',
  FUTURE: 'future',
};

/**
 * Classifica o vencimento. A comparacao e por dia do calendario e nao por diferenca de horas:
 * as 23h, algo que vence as 8h de amanha esta a nove horas de distancia, mas para quem le o
 * quadro e "amanha", nao "hoje".
 */
export const dueState = (dueAt, now = new Date()) => {
  if (!dueAt) return null;

  const due = new Date(dueAt);
  if (Number.isNaN(due.getTime())) return null;

  const startOfDay = date =>
    new Date(date.getFullYear(), date.getMonth(), date.getDate()).getTime();

  const days = Math.round((startOfDay(due) - startOfDay(now)) / DAY);
  if (due.getTime() < now.getTime() && days <= 0) return DUE_STATES.OVERDUE;
  if (days <= 0) return DUE_STATES.TODAY;
  if (days === 1) return DUE_STATES.TOMORROW;

  return DUE_STATES.FUTURE;
};

// Prioridade nao pode depender so de cor: o PRD pede icone e texto por acessibilidade, e um
// quadro cheio de bolinhas coloridas nao se le em escala de cinza nem por quem nao distingue
// vermelho de verde.
export const PRIORITY_META = {
  urgent: { icon: 'i-lucide-chevrons-up', tone: 'ruby' },
  high: { icon: 'i-lucide-chevron-up', tone: 'amber' },
  medium: { icon: 'i-lucide-equal', tone: 'blue' },
  low: { icon: 'i-lucide-chevron-down', tone: 'slate' },
};

export const TASK_PRIORITIES = ['low', 'medium', 'high', 'urgent'];

export const STAGE_TYPES = ['open', 'won', 'lost'];

export const BOARD_TEMPLATES = ['clinic', 'blank'];

export const BOARD_MEMBER_ROLES = ['manager', 'member', 'viewer'];

export const VISIBILITY_SCOPES = ['all_tasks', 'own_tasks'];

/**
 * Valor formatado na moeda do quadro. Cai para o codigo cru quando a moeda nao e reconhecida
 * pelo navegador: mostrar "XYZ 1.500" informa mais do que estourar ou esconder o numero.
 */
export const formatMoney = (value, currency = 'BRL', locale = 'pt-BR') => {
  const amount = Number(value ?? 0);
  if (!Number.isFinite(amount)) return '';

  try {
    return new Intl.NumberFormat(locale, {
      style: 'currency',
      currency,
      maximumFractionDigits: 0,
    }).format(amount);
  } catch {
    return `${currency} ${Math.round(amount).toLocaleString(locale)}`;
  }
};
