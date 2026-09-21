import {
  camelizeFunnelPayload,
  compareRank,
  sortByRank,
  groupTasksByStep,
  neighboursAt,
  waitingState,
  WAITING_LEVELS,
  stageAge,
  boardMetrics,
  dueState,
  DUE_STATES,
  filterTasks,
  sortTasks,
  DUE_FILTERS,
  hasActiveFilters,
  EMPTY_FILTERS,
} from '../funnelHelper';

describe('funnelHelper', () => {
  describe('compareRank', () => {
    it('orders by integer part before falling back to the fraction', () => {
      expect(compareRank('65536', '131072')).toBe(-1);
      expect(compareRank('131072', '65536')).toBe(1);
      expect(compareRank('65536.0', '65536')).toBe(0);
    });

    it('separates ranks that a float would collapse', () => {
      // 15 casas decimais: Number() igualaria os dois e a ordem viraria sorte.
      const left = '65536.000000000000001';
      const right = '65536.000000000000002';

      expect(compareRank(left, right)).toBe(-1);
      expect(Number(left) === Number(right)).toBe(true);
    });

    it('handles the negative ranks that prepend_before produces', () => {
      expect(compareRank('-65536', '0')).toBe(-1);
      expect(compareRank('-131072', '-65536')).toBe(-1);
      expect(compareRank('-0.5', '-0.25')).toBe(-1);
      expect(compareRank('-0', '0')).toBe(0);
    });
  });

  describe('sortByRank', () => {
    it('sorts a copy and leaves the input untouched', () => {
      const tasks = [
        { id: 1, rank: '131072' },
        { id: 2, rank: '65536' },
      ];

      expect(sortByRank(tasks).map(task => task.id)).toEqual([2, 1]);
      expect(tasks.map(task => task.id)).toEqual([1, 2]);
    });
  });

  describe('groupTasksByStep', () => {
    const steps = [{ id: 10 }, { id: 20 }];

    it('buckets tasks per step, each bucket ordered by rank', () => {
      const grouped = groupTasksByStep(steps, [
        { id: 1, funnelStepId: 10, rank: '131072' },
        { id: 2, funnelStepId: 20, rank: '65536' },
        { id: 3, funnelStepId: 10, rank: '65536' },
      ]);

      expect(grouped[10].map(task => task.id)).toEqual([3, 1]);
      expect(grouped[20].map(task => task.id)).toEqual([2]);
    });

    it('keeps an empty bucket for a step with no tasks', () => {
      expect(groupTasksByStep(steps, [])).toEqual({ 10: [], 20: [] });
    });

    it('drops tasks whose step is not on the board', () => {
      const grouped = groupTasksByStep(steps, [
        { id: 1, funnelStepId: 99, rank: '65536' },
      ]);

      expect(grouped).toEqual({ 10: [], 20: [] });
    });
  });

  describe('waitingState', () => {
    const now = new Date('2026-03-10T12:00:00Z').getTime();
    const ago = ms => new Date(now - ms).toISOString();
    const MIN = 60 * 1000;

    it('counts minutes below an hour', () => {
      expect(waitingState(ago(55 * MIN), now).label).toBe('55min');
    });

    it('counts hours below a day, then days', () => {
      expect(waitingState(ago(3 * 60 * MIN), now).label).toBe('3h');
      expect(waitingState(ago(12 * 24 * 60 * MIN), now).label).toBe('12d');
    });

    // Card recem chegado mostra 1min e nao 0min: zero parece defeito, e o minuto seguinte corrige.
    it('never shows zero for a customer who just wrote', () => {
      expect(waitingState(ago(2000), now).label).toBe('1min');
    });

    // A escala inteira, nos limites: a primeira hora ainda e o ritmo normal do atendimento e a
    // quarta e onde o cliente ja desistiu. Sao os dois pontos em que a cor do card muda.
    it('turns amber at one hour and ruby at four', () => {
      expect(waitingState(ago(59 * MIN), now).level).toBe(WAITING_LEVELS.CALM);
      expect(waitingState(ago(60 * MIN), now).level).toBe(WAITING_LEVELS.WARN);
      expect(waitingState(ago(239 * MIN), now).level).toBe(WAITING_LEVELS.WARN);
      expect(waitingState(ago(240 * MIN), now).level).toBe(
        WAITING_LEVELS.ALERT
      );
    });

    // Sem conversa vinculada nao ha relogio: o card nao mostra selo nenhum, em vez de mostrar
    // um zero que afirmaria que ninguem esta esperando.
    it('returns null for a missing or invalid timestamp', () => {
      expect(waitingState(null, now)).toBeNull();
      expect(waitingState('nao e data', now)).toBeNull();
    });
  });

  describe('stageAge', () => {
    const now = new Date('2026-03-10T12:00:00Z').getTime();
    const ago = ms => new Date(now - ms).toISOString();
    const MIN = 60 * 1000;

    it('reads the same short scale as the waiting clock', () => {
      expect(stageAge(ago(55 * MIN), now).label).toBe('55min');
      expect(stageAge(ago(3 * 60 * MIN), now).label).toBe('3h');
      expect(stageAge(ago(12 * 24 * 60 * MIN), now).label).toBe('12d');
    });

    // A pergunta que o relogio do cliente nao responde: com o agente tendo respondido por ultimo
    // o waiting_since e nulo, e sem isto a coluna inteira ficava sem nocao de tempo.
    it('answers even when nobody owes a reply', () => {
      expect(waitingState(null, now)).toBeNull();
      expect(stageAge(ago(3 * 24 * 60 * MIN), now).label).toBe('3d');
    });

    it('returns null for a missing or invalid timestamp', () => {
      expect(stageAge(null, now)).toBeNull();
      expect(stageAge('nao e data', now)).toBeNull();
    });
  });

  describe('dueState', () => {
    const now = new Date('2026-03-10T23:00:00');

    it('marks a past due date as overdue', () => {
      expect(dueState('2026-03-09T10:00:00', now)).toBe(DUE_STATES.OVERDUE);
    });

    it('marks today as today even when the hour already passed', () => {
      expect(dueState('2026-03-10T08:00:00', now)).toBe(DUE_STATES.OVERDUE);
    });

    it('marks a later hour today as today', () => {
      expect(dueState('2026-03-10T23:30:00', now)).toBe(DUE_STATES.TODAY);
    });

    // As 23h, algo que vence as 8h de amanha esta a nove horas — mas para quem le o quadro e
    // "amanha". A classificacao e por dia do calendario, nao por diferenca de horas.
    it('marks tomorrow morning as tomorrow and not today', () => {
      expect(dueState('2026-03-11T08:00:00', now)).toBe(DUE_STATES.TOMORROW);
    });

    it('marks anything further out as future', () => {
      expect(dueState('2026-03-20T08:00:00', now)).toBe(DUE_STATES.FUTURE);
    });

    it('returns null without a due date', () => {
      expect(dueState(null, now)).toBeNull();
    });
  });

  describe('filterTasks', () => {
    const tasks = [
      {
        id: 1,
        title: 'Retorno da Maria',
        description: 'trazer exame',
        priority: 'high',
        assignees: [{ id: 10 }],
        labels: [{ id: 100 }],
        channel: { inboxId: 5 },
      },
      {
        id: 2,
        title: 'Primeira consulta',
        priority: 'low',
        assignees: [{ id: 20 }],
        labels: [],
        channel: { inboxId: 6 },
      },
      { id: 3, title: 'Sem nada' },
    ];

    it('returns everything with empty filters', () => {
      expect(filterTasks(tasks, EMPTY_FILTERS)).toHaveLength(3);
    });

    it('searches the title and the description', () => {
      expect(filterTasks(tasks, { search: 'maria' }).map(t => t.id)).toEqual([
        1,
      ]);
      expect(filterTasks(tasks, { search: 'exame' }).map(t => t.id)).toEqual([
        1,
      ]);
    });

    it('ignores a search of only spaces', () => {
      expect(filterTasks(tasks, { search: '   ' })).toHaveLength(3);
    });

    it('filters by assignee, inbox, priority and label', () => {
      expect(filterTasks(tasks, { assigneeId: 20 }).map(t => t.id)).toEqual([
        2,
      ]);
      expect(filterTasks(tasks, { inboxId: 5 }).map(t => t.id)).toEqual([1]);
      expect(filterTasks(tasks, { priority: 'high' }).map(t => t.id)).toEqual([
        1,
      ]);
      expect(filterTasks(tasks, { labelId: 100 }).map(t => t.id)).toEqual([1]);
    });

    it('combines filters', () => {
      expect(filterTasks(tasks, { priority: 'high', assigneeId: 20 })).toEqual(
        []
      );
    });

    // Card sem responsavel, sem canal ou sem etiqueta nao pode passar por um filtro desses.
    it('drops a card that has none of the filtered attribute', () => {
      expect(filterTasks(tasks, { assigneeId: 10 }).map(t => t.id)).toEqual([
        1,
      ]);
      expect(filterTasks(tasks, { inboxId: 5 }).map(t => t.id)).not.toContain(
        3
      );
    });
  });

  describe('filtering by due date', () => {
    const iso = days => new Date(Date.now() + days * 86400000).toISOString();
    const tasks = [
      { id: 1, dueAt: iso(-2) },
      { id: 2, dueAt: iso(0.2) },
      { id: 3, dueAt: iso(3) },
      { id: 4, dueAt: iso(30) },
      { id: 5, dueAt: null },
    ];

    it('offers the four ranges the board is asked about', () => {
      expect(DUE_FILTERS).toEqual(['overdue', 'today', 'week', 'none']);
    });

    it('finds what is overdue', () => {
      expect(filterTasks(tasks, { due: 'overdue' }).map(t => t.id)).toEqual([
        1,
      ]);
    });

    it('finds what is due within a week, leaving out what is already late', () => {
      expect(filterTasks(tasks, { due: 'week' }).map(t => t.id)).toEqual([
        2, 3,
      ]);
    });

    // Ausencia de prazo e um filtro proprio: nenhum estado de vencimento descreve isso.
    it('finds the cards with no due date at all', () => {
      expect(filterTasks(tasks, { due: 'none' }).map(t => t.id)).toEqual([5]);
    });
  });

  describe('filtering by custom attribute', () => {
    const tasks = [
      { id: 1, customAttributes: { plano: 'ouro', origem: 'indicacao' } },
      { id: 2, customAttributes: { plano: 'prata' } },
      { id: 3, customAttributes: {} },
      { id: 4 },
    ];

    it('filters by the presence of the key when no value is given', () => {
      expect(
        filterTasks(tasks, { attributeKey: 'plano' }).map(t => t.id)
      ).toEqual([1, 2]);
    });

    it('filters by value when one is given', () => {
      expect(
        filterTasks(tasks, {
          attributeKey: 'plano',
          attributeValue: 'ouro',
        }).map(t => t.id)
      ).toEqual([1]);
    });

    // Os dois lados sao digitados por pessoas; exigir a caixa exata daria zero resultado a toa.
    it('ignores letter case in the value', () => {
      expect(
        filterTasks(tasks, {
          attributeKey: 'plano',
          attributeValue: 'OURO',
        }).map(t => t.id)
      ).toEqual([1]);
    });

    it('survives a card with no attributes at all', () => {
      expect(
        filterTasks(tasks, { attributeKey: 'plano' }).map(t => t.id)
      ).not.toContain(4);
    });
  });

  describe('hasActiveFilters', () => {
    it('is false for the empty set and true for anything set', () => {
      expect(hasActiveFilters(EMPTY_FILTERS)).toBe(false);
      expect(hasActiveFilters({ ...EMPTY_FILTERS, priority: 'low' })).toBe(
        true
      );
      expect(hasActiveFilters({ ...EMPTY_FILTERS, search: 'x' })).toBe(true);
    });
  });

  describe('sortTasks', () => {
    const tasks = [
      { id: 1, rank: '300', priority: 'low', title: 'C', dueAt: '2026-03-20' },
      { id: 2, rank: '100', priority: 'urgent', title: 'A', dueAt: null },
      { id: 3, rank: '200', priority: null, title: 'B', dueAt: '2026-03-10' },
    ];

    it('falls back to the fractional rank', () => {
      expect(sortTasks(tasks, 'position').map(t => t.id)).toEqual([2, 3, 1]);
    });

    it('puts the most urgent first and breaks ties by position', () => {
      expect(sortTasks(tasks, 'priority').map(t => t.id)).toEqual([2, 1, 3]);
    });

    // Sem prazo nao e "prazo antigo": esses cards vao para o fim, nao para o topo.
    it('sorts by due date leaving the ones without a date last', () => {
      expect(sortTasks(tasks, 'due').map(t => t.id)).toEqual([3, 1, 2]);
    });

    it('sorts by title', () => {
      expect(sortTasks(tasks, 'title').map(t => t.id)).toEqual([2, 3, 1]);
    });

    it('does not mutate the given list', () => {
      const original = tasks.map(t => t.id);
      sortTasks(tasks, 'title');
      expect(tasks.map(t => t.id)).toEqual(original);
    });

    // A ordem padrao do quadro. Quem espera ha mais tempo primeiro, e card sem relogio por
    // ultimo: ausencia de espera nao e espera zero nem infinita.
    it('puts the longest wait first and cards without a clock last', () => {
      const hoursAgo = hours =>
        new Date(Date.now() - hours * 60 * 60 * 1000).toISOString();
      const waiting = [
        { id: 1, rank: '300', waitingSince: hoursAgo(1) },
        { id: 2, rank: '100', waitingSince: null },
        { id: 3, rank: '200', waitingSince: hoursAgo(6) },
      ];

      expect(sortTasks(waiting, 'waiting').map(t => t.id)).toEqual([3, 1, 2]);
    });
  });

  describe('boardMetrics', () => {
    const steps = [
      { id: 10, stageType: 'open' },
      { id: 20, stageType: 'open' },
      { id: 30, stageType: 'won' },
    ];
    const hoursAgo = hours =>
      new Date(Date.now() - hours * 60 * 60 * 1000).toISOString();

    const tasks = [
      { id: 1, funnelStepId: 10, value: '1000', waitingSince: hoursAgo(2) },
      { id: 2, funnelStepId: 20, value: '500', waitingSince: hoursAgo(0.2) },
      { id: 3, funnelStepId: 10, value: null, waitingSince: null },
      {
        id: 4,
        funnelStepId: 30,
        value: '9000',
        createdAt: '2026-03-01T00:00:00Z',
        stepChangedAt: '2026-03-05T00:00:00Z',
      },
    ];

    // O que esta fechado nao conta como oportunidade nem soma ao valor em aberto: um funil que
    // somasse os ganhos no "em aberto" cresceria para sempre e nunca mais cairia.
    it('counts only the open stages as pipeline', () => {
      const metrics = boardMetrics(tasks, steps);

      expect(metrics.opportunities).toBe(3);
      expect(metrics.openValue).toBe(1500);
    });

    // Dentro da primeira hora ainda e o ritmo normal: so conta quem passou dela.
    it('counts as waiting only the cards past the first hour', () => {
      expect(boardMetrics(tasks, steps).waiting).toBe(1);
    });

    it('measures the cycle on what closed, and stays null while nothing has', () => {
      expect(boardMetrics(tasks, steps).cycleDays).toBe(4);
      expect(boardMetrics(tasks.slice(0, 3), steps).cycleDays).toBeNull();
    });

    // "Avancou" e ter saido da primeira etapa da fileira.
    it('counts as advanced what left the entry stage', () => {
      expect(boardMetrics(tasks, steps).advanced).toBe(1);
    });
  });

  describe('neighboursAt', () => {
    const tasks = [{ id: 1 }, { id: 2 }, { id: 3 }];

    it('reads the neighbours around the card', () => {
      expect(neighboursAt(tasks, 2)).toEqual({ afterId: 1, beforeId: 3 });
    });

    it('returns null on the edge the card sits on', () => {
      expect(neighboursAt(tasks, 1)).toEqual({ afterId: null, beforeId: 2 });
      expect(neighboursAt(tasks, 3)).toEqual({ afterId: 2, beforeId: null });
    });

    it('returns no anchors when the card is not in the list', () => {
      expect(neighboursAt(tasks, 99)).toEqual({
        afterId: null,
        beforeId: null,
      });
    });
  });
});

describe('camelizeFunnelPayload', () => {
  // O bug que este teste existe para impedir: a tela mostrava todas as automacoes desligadas
  // enquanto o servidor respondia 200 com elas ligadas. camelize renomeava a CHAVE da regra.
  it('keeps the automation rule names exactly as the backend stores them', () => {
    const board = camelizeFunnelPayload({
      board_step_id: 3,
      automation_settings: { create_task_on_conversation: true },
    });

    expect(board.boardStepId).toBe(3);
    expect(board.automationSettings).toEqual({
      create_task_on_conversation: true,
    });
  });

  it('keeps the custom attribute names the customer chose', () => {
    const task = camelizeFunnelPayload({
      custom_attributes: { estagio_do_lead: 'novo', plano_do_paciente: 'ouro' },
    });

    expect(task.customAttributes).toEqual({
      estagio_do_lead: 'novo',
      plano_do_paciente: 'ouro',
    });
  });

  // A listagem chega como array, e e por ali que a tela carrega o quadro no primeiro acesso.
  it('protects the same dictionaries inside a list', () => {
    const [board] = camelizeFunnelPayload([
      {
        inbox_ids: [1],
        automation_settings: { resolve_conversation_on_final_step: true },
      },
    ]);

    expect(board.inboxIds).toEqual([1]);
    expect(board.automationSettings).toEqual({
      resolve_conversation_on_final_step: true,
    });
  });

  it('survives a null payload', () => {
    expect(camelizeFunnelPayload(null)).toEqual({});
  });
});
