import {
  compareRank,
  sortByRank,
  groupTasksByStep,
  neighboursAt,
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
