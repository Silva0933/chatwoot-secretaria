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

/**
 * Distribui os cards nas etapas do quadro, cada lista ja ordenada por rank.
 * Cards cuja etapa nao existe mais na resposta ficam de fora, em vez de sumir numa coluna
 * fantasma.
 */
export const groupTasksByStep = (steps = [], tasks = []) => {
  const grouped = Object.fromEntries(steps.map(step => [step.id, []]));

  tasks.forEach(task => {
    if (grouped[task.funnelStepId]) grouped[task.funnelStepId].push(task);
  });

  Object.keys(grouped).forEach(stepId => {
    grouped[stepId] = sortByRank(grouped[stepId]);
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

export const TASK_PRIORITIES = ['low', 'medium', 'high', 'urgent'];

export const STAGE_TYPES = ['open', 'won', 'lost'];

export const BOARD_TEMPLATES = ['clinic', 'blank'];
