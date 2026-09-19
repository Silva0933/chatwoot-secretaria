/**
 * Helpers do modulo Funnel (quadro Kanban).
 *
 * O rank chega da API como string e nao como numero: a coluna e decimal(30,15) e
 * `JSON.parse` transformaria "65536.000000000000001" num float, perdendo justamente as casas
 * que separam dois cards vizinhos. Toda comparacao aqui e feita sobre a string.
 */

import camelcaseKeys from 'camelcase-keys';

const MINUTE = 60 * 1000;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;

/**
 * Dicionarios de chave livre no payload do Funnel. A chave ali e DADO — o nome de uma regra de
 * automacao, o nome de um atributo que o cliente inventou — e nao nome de campo da API, entao
 * camelizar renomeia informacao. `create_task_on_conversation` virava `createTaskOnConversation`
 * e sumia para quem procurasse pelo nome real, que e o que o backend guarda e o que a tela usa.
 *
 * Mora aqui, e nao no store, para caber num teste: o sintoma e uma tela que mostra tudo
 * desligado enquanto o servidor responde 200 com tudo ligado, e nada nesse caminho quebra alto.
 */
export const FREE_FORM_DICTIONARIES = [
  'custom_attributes',
  'automation_settings',
];

export const camelizeFunnelPayload = data =>
  camelcaseKeys(data ?? {}, { deep: true, stopPaths: FREE_FORM_DICTIONARIES });

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

// 'waiting' primeiro e como padrao: a pergunta que abre um funil de manha e "quem esta
// esperando ha mais tempo", nao "em que ordem eu arrastei os cards". A ordem por posicao
// continua ali para quem organiza a coluna a mao, e e ela que libera o arrastar.
export const SORT_OPTIONS = [
  'waiting',
  'position',
  'priority',
  'due',
  'created',
  'updated',
  'title',
];

export const DEFAULT_SORT = 'waiting';

// Filtro de prazo em faixas nomeadas, nao em duas datas. "Vence hoje" e "atrasado" sao as
// perguntas que alguem faz olhando um funil; um seletor de intervalo pede duas decisoes para
// responder a mesma coisa.
export const DUE_FILTERS = ['overdue', 'today', 'week', 'none'];

// Faixas de espera, e nao um campo de minutos: "quem esta esperando ha mais de uma hora" e a
// pergunta real; um numero livre pede uma decisao para responder a mesma coisa.
export const WAITING_FILTERS = ['any', 'over_1h', 'over_4h'];

export const EMPTY_FILTERS = Object.freeze({
  search: '',
  assigneeId: null,
  inboxId: null,
  priority: null,
  labelId: null,
  due: null,
  waiting: null,
  attributeKey: '',
  attributeValue: '',
});

export const hasActiveFilters = filters =>
  Object.entries(EMPTY_FILTERS).some(
    ([key, empty]) => (filters?.[key] ?? empty) !== empty
  );

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

/**
 * Duracao no formato curto do quadro: 12min, 3h, 12d.
 *
 * Curto de proposito. E um sinal de triagem lido de relance em dezenas de cards ao mesmo tempo,
 * nao uma data — "ha 3 dias" ocuparia a linha inteira e diria a mesma coisa.
 */
const shortDuration = elapsed => {
  // Nunca zero: um card que acabou de chegar mostrando "0min" parece defeito, e o minuto
  // seguinte corrige sozinho.
  if (elapsed < HOUR) return `${Math.max(Math.floor(elapsed / MINUTE), 1)}min`;
  if (elapsed < DAY) return `${Math.floor(elapsed / HOUR)}h`;

  return `${Math.floor(elapsed / DAY)}d`;
};

export const WAITING_LEVELS = {
  CALM: 'calm',
  WARN: 'warn',
  ALERT: 'alert',
};

// Uma hora e quatro horas. Nao sao numeros redondos por acaso: dentro da primeira hora a
// resposta ainda esta no ritmo normal do atendimento, depois de quatro o cliente ja desistiu de
// esperar. O meio e onde vale a pena avisar antes de virar problema.
export const WAITING_WARN_AFTER = HOUR;
export const WAITING_ALERT_AFTER = 4 * HOUR;

/**
 * Ha quanto tempo o CLIENTE espera resposta — o relogio dele, nao o da etapa.
 *
 * Vem de `waiting_since` da conversa, que o Chatwoot zera quando um agente responde e volta a
 * marcar quando o cliente escreve de novo. Um card pode estar tres dias parado em "Proposta
 * enviada" sem ninguem devendo nada: tempo na etapa e tempo de espera sao perguntas diferentes,
 * e era a segunda que faltava no quadro.
 */
export const waitingState = (waitingSince, now = Date.now()) => {
  if (!waitingSince) return null;

  const since = new Date(waitingSince).getTime();
  if (Number.isNaN(since)) return null;

  const elapsed = Math.max(now - since, 0);

  let level = WAITING_LEVELS.CALM;
  if (elapsed >= WAITING_ALERT_AFTER) level = WAITING_LEVELS.ALERT;
  else if (elapsed >= WAITING_WARN_AFTER) level = WAITING_LEVELS.WARN;

  return { elapsed, level, label: shortDuration(elapsed) };
};

/**
 * Urgencia em tres niveis e nao nas quatro prioridades do card.
 *
 * Baixa e media nao ganham marca nenhuma. Sao o estado da maioria — o importador legado marcou
 * como media todo card que veio sem escolha — e marcar a maioria nao informa nada: so faz o
 * urgente competir com ruido. As quatro prioridades continuam existindo no dialogo do card; o
 * que muda e quantas delas merecem um simbolo no quadro.
 *
 * Sempre icone E cor, nunca cor sozinha: uma seta e duas setas sao formas diferentes, e e isso
 * que sobrevive a escala de cinza e a quem nao distingue ambar de vermelho.
 */
export const URGENCY_META = {
  urgent: { icon: 'i-lucide-chevrons-up', tone: 'ruby' },
  high: { icon: 'i-lucide-chevron-up', tone: 'amber' },
};

const matchesDue = (task, wanted) => {
  const state = dueState(task.dueAt);

  // "Sem prazo" e um filtro por ausencia: precisa casar com o card que nao tem data, e nenhum
  // estado descreve isso — dueState devolve null.
  if (wanted === 'none') return state === null;
  if (state === null) return false;

  if (wanted === 'overdue') return state === DUE_STATES.OVERDUE;
  if (wanted === 'today') return state === DUE_STATES.TODAY;
  if (wanted === 'week') {
    const days = (new Date(task.dueAt) - Date.now()) / (24 * 60 * 60 * 1000);
    return state !== DUE_STATES.OVERDUE && days <= 7;
  }

  return true;
};

// Chave sozinha filtra por presenca do atributo; com valor, por valor. Comparacao por texto e
// sem diferenciar maiuscula: o atributo e digitado pelo usuario nos dois lados.
const matchesAttribute = (task, filters) => {
  const key = filters.attributeKey?.trim();
  if (!key) return true;

  const attributes = task.customAttributes ?? {};
  if (!(key in attributes)) return false;

  const wanted = filters.attributeValue?.trim();
  if (!wanted) return true;

  return String(attributes[key] ?? '')
    .toLowerCase()
    .includes(wanted.toLowerCase());
};

// A espera vem da conversa; card sem conversa vinculada nao tem relogio e por isso nunca casa
// com um filtro de espera — "esperando ha mais de 1h" e uma afirmacao sobre alguem do outro
// lado, e ali nao ha ninguem.
const matchesWaiting = (task, wanted) => {
  const waiting = waitingState(task.waitingSince);
  if (!waiting) return false;

  if (wanted === 'over_1h') return waiting.elapsed >= WAITING_WARN_AFTER;
  if (wanted === 'over_4h') return waiting.elapsed >= WAITING_ALERT_AFTER;

  return true;
};

const matchesSearch = (task, term) => {
  if (!term) return true;

  const needle = term.trim().toLowerCase();
  if (!needle) return true;

  // O trecho entra na busca junto de titulo e descricao: ele e o texto que o operador acabou
  // de ler no card, e procurar por uma palavra que esta na tela sem achar o card parece defeito.
  return [task.title, task.description, task.excerpt]
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

    if (filters.due && !matchesDue(task, filters.due)) return false;

    if (filters.waiting && !matchesWaiting(task, filters.waiting)) return false;

    if (!matchesAttribute(task, filters)) return false;

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

export const sortTasks = (tasks = [], sortBy = DEFAULT_SORT) => {
  const copy = [...tasks];

  switch (sortBy) {
    case 'waiting':
      // Quem espera ha mais tempo primeiro. Card sem espera vai para o fim e nao para o topo:
      // ausencia de relogio nao e espera zero nem espera infinita — e pergunta que nao se
      // aplica, e o desempate por posicao mantem esses estaveis entre si.
      return copy.sort((left, right) => {
        const a = waitingState(left.waitingSince);
        const b = waitingState(right.waitingSince);
        if (!a && !b) return compareRank(left.rank, right.rank);
        if (!a) return 1;
        if (!b) return -1;

        return b.elapsed - a.elapsed || compareRank(left.rank, right.rank);
      });
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
  sortBy = DEFAULT_SORT
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

export const TASK_PRIORITIES = ['low', 'medium', 'high', 'urgent'];

export const STAGE_TYPES = ['open', 'won', 'lost'];

/**
 * Paleta das etapas. Seis opcoes e nao oito, e a escolha foi medida e nao estetica: turquesa e
 * verde separam por dE 9,3 em visao normal, violeta e azul por 11,5 — os dois abaixo do piso de
 * 15, ou seja, dificeis de distinguir mesmo por quem enxerga todas as cores. Ficaram de fora.
 * Nesta ordem, o pior par vizinho e verde<->rosa: dE 9,0 em deuteranopia e 23,1 em visao normal.
 *
 * A ardosia e propositalmente sem croma: e a opcao "sem cor", para etapa que nao quer destaque.
 *
 * Nada disso torna a cor confiavel sozinha — um seletor livre nunca torna, porque quem ordena as
 * colunas e o usuario e qualquer par pode acabar lado a lado. Por isso o cabecalho da coluna traz
 * o nome da etapa e o icone de ganho/perdido: a cor agrupa, o texto identifica.
 */
export const STEP_COLORS = [
  { value: '#64748B', key: 'SLATE' },
  { value: '#E5484D', key: 'RED' },
  { value: '#2D8FE0', key: 'BLUE' },
  { value: '#C77D11', key: 'AMBER' },
  { value: '#D6409F', key: 'PINK' },
  { value: '#2E9E5B', key: 'GREEN' },
];

export const DEFAULT_STEP_COLOR = STEP_COLORS[2].value;

// 'blank' primeiro e como padrao: 'clinic' e heranca da origem da fazer.ai e traz oito etapas
// de jornada de paciente, que nao descrevem a maioria das contas. Quem quer a de clinica
// escolhe; quem nao quer nao precisa apagar oito etapas para comecar.
export const BOARD_TEMPLATES = ['blank', 'clinic'];

export const BOARD_MEMBER_ROLES = ['manager', 'member', 'viewer'];

export const VISIBILITY_SCOPES = ['all_tasks', 'own_tasks'];

// Mesma ordem e mesmos nomes de Funnel::Automations::Runner::RULES. Um nome divergente aqui
// grava uma chave que o motor nunca le, e a automacao fica ligada na tela sem nunca rodar.
export const AUTOMATION_RULES = [
  'create_task_on_conversation',
  'auto_assign_task',
  'win_task_on_conversation_resolved',
  'resolve_conversation_on_final_step',
  'sync_assignees',
  'sync_labels_and_priority',
];

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

/**
 * A faixa de metricas do cabecalho do quadro.
 *
 * Tudo sai dos cards que ja estao na tela e respeita o filtro, como os contadores das colunas:
 * uma faixa que ignorasse o filtro contaria um quadro que ninguem esta vendo. Nada disso pede
 * uma segunda consulta ao servidor — o quadro ja carrega os cards ativos de uma vez.
 */
export const boardMetrics = (tasks = [], steps = []) => {
  const openStepIds = new Set(
    steps
      .filter(step => (step.stageType || 'open') === 'open')
      .map(step => step.id)
  );
  // A etapa de entrada e a primeira da fileira: dela para a frente o card "avancou".
  const entryStepId = steps[0]?.id ?? null;

  const open = tasks.filter(task => openStepIds.has(task.funnelStepId));

  const waiting = open.filter(task => {
    const state = waitingState(task.waitingSince);
    return state && state.level !== WAITING_LEVELS.CALM;
  }).length;

  const advanced = open.filter(
    task => task.funnelStepId !== entryStepId
  ).length;

  // Ciclo medio do que fechou, ganho ou perdido: quanto tempo um card leva da criacao ate sair
  // do funil. Medir isso no que ainda esta aberto responderia "ha quanto tempo estao em aberto",
  // que e outra pergunta e so cresce.
  const closed = tasks.filter(
    task => !openStepIds.has(task.funnelStepId) && task.createdAt
  );
  const cycleMs = closed.reduce((total, task) => {
    const from = new Date(task.createdAt).getTime();
    const to = new Date(task.stepChangedAt ?? task.updatedAt).getTime();
    if (Number.isNaN(from) || Number.isNaN(to)) return total;

    return total + Math.max(to - from, 0);
  }, 0);

  return {
    openValue: open.reduce((total, task) => {
      const amount = Number(task.value);
      return Number.isFinite(amount) ? total + amount : total;
    }, 0),
    opportunities: open.length,
    // Sem nada fechado ainda, o ciclo e null e nao zero: "0d" afirmaria que os cards fecham no
    // mesmo dia, quando o que se sabe e que nenhum fechou.
    cycleDays: closed.length ? Math.round(cycleMs / closed.length / DAY) : null,
    waiting,
    advanced,
  };
};
