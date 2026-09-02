import {
  compareRank,
  sortByRank,
  groupTasksByStep,
  neighboursAt,
  timeInStep,
  dueState,
  DUE_STATES,
  filterTasks,
  sortTasks,
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

  describe('timeInStep', () => {
    const now = new Date('2026-03-10T12:00:00Z').getTime();
    const ago = ms => new Date(now - ms).toISOString();

    it('counts minutes below an hour', () => {
      expect(timeInStep(ago(55 * 60 * 1000), now)).toBe('55m');
    });

    it('counts hours below a day', () => {
      expect(timeInStep(ago(3 * 60 * 60 * 1000), now)).toBe('3h');
    });

    it('counts days beyond that', () => {
      expect(timeInStep(ago(12 * 24 * 60 * 60 * 1000), now)).toBe('12d');
    });

    // Card recem movido mostra 1m e nao 0m: zero parece defeito, e o minuto seguinte corrige.
    it('never shows zero for a card just moved', () => {
      expect(timeInStep(ago(2000), now)).toBe('1m');
    });

    it('returns empty for a missing or invalid timestamp', () => {
      expect(timeInStep(null, now)).toBe('');
      expect(timeInStep('nao e data', now)).toBe('');
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
