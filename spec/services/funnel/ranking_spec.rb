require 'rails_helper'

RSpec.describe Funnel::Ranking do
  describe '.between' do
    it 'returns the midpoint of both neighbours' do
      expect(described_class.between(BigDecimal('10'), BigDecimal('20'))).to eq(BigDecimal('15'))
    end

    it 'appends after the last card when there is no next neighbour' do
      expect(described_class.between(BigDecimal('10'), nil)).to eq(BigDecimal('10') + described_class::STEP)
    end

    it 'prepends before the first card when there is no previous neighbour' do
      expect(described_class.between(nil, BigDecimal('10'))).to eq(BigDecimal('10') - described_class::STEP)
    end

    it 'returns the base step for an empty column' do
      expect(described_class.between(nil, nil)).to eq(described_class::STEP)
    end

    it 'keeps the new rank strictly between the neighbours' do
      previous = BigDecimal('1')
      following = BigDecimal('2')

      rank = described_class.between(previous, following)

      expect(rank).to be > previous
      expect(rank).to be < following
    end
  end

  describe '.rebalance_needed?' do
    it 'is false for neighbours that are far apart' do
      expect(described_class.rebalance_needed?(BigDecimal('1'), BigDecimal('2'))).to be false
    end

    it 'is true once the gap no longer fits another midpoint safely' do
      previous = BigDecimal('1')
      following = previous + (described_class::MIN_GAP / 2)

      expect(described_class.rebalance_needed?(previous, following)).to be true
    end

    it 'is false when a neighbour is missing' do
      expect(described_class.rebalance_needed?(nil, BigDecimal('1'))).to be false
    end

    # Este e o caso que justifica o rebalanceamento existir: inserir sempre no mesmo intervalo
    # divide o gap pela metade a cada vez, e decimal(30,15) esgota antes de 60 insercoes.
    it 'signals a rebalance before the column runs out of precision' do
      previous = BigDecimal('0')
      following = BigDecimal('1')
      insertions = 0

      until described_class.rebalance_needed?(previous, following)
        following = described_class.between(previous, following)
        insertions += 1
        raise 'rebalance was never signalled' if insertions > 200
      end

      expect(insertions).to be < 60
      expect(following).to be > previous
    end
  end

  describe '.rebalance' do
    it 'redistributes ranks in even intervals preserving order' do
      result = described_class.rebalance([7, 3, 9])

      expect(result.keys).to eq([7, 3, 9])
      expect(result.values).to eq([described_class::STEP * 1, described_class::STEP * 2, described_class::STEP * 3])
    end

    it 'returns an empty map for an empty column' do
      expect(described_class.rebalance([])).to eq({})
    end
  end
end
