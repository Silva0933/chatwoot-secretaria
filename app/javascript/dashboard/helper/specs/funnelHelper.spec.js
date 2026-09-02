import {
  compareRank,
  sortByRank,
  groupTasksByStep,
  neighboursAt,
  timeInStep,
  dueState,
  DUE_STATES,
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
