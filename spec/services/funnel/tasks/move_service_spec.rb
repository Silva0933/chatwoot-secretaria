require 'rails_helper'

RSpec.describe Funnel::Tasks::MoveService do
  let(:account) { create(:account) }
  let(:board) { create(:funnel_board, account: account) }
  let(:origin_step) { create(:funnel_step, board: board) }
  let(:target_step) { create(:funnel_step, board: board) }
  let(:agent) { create(:user, account: account) }
  let(:task) { create(:funnel_task, board_for_task: board, step: origin_step) }

  describe '#perform' do
    it 'moves a card to another step' do
      described_class.new(task: task, step: target_step).perform

      expect(task.reload.funnel_step_id).to eq(target_step.id)
    end

    it 'places the card between the two neighbours it was dropped on' do
      above = create(:funnel_task, board_for_task: board, step: target_step)
      below = create(:funnel_task, board_for_task: board, step: target_step)

      described_class.new(task: task, step: target_step, after_id: above.id, before_id: below.id).perform

      expect(task.reload.rank).to be > above.rank
      expect(task.rank).to be < below.rank
    end

    it 'appends to the end when dropped below the last card' do
      last = create(:funnel_task, board_for_task: board, step: target_step)

      described_class.new(task: task, step: target_step, after_id: last.id).perform

      expect(task.reload.rank).to be > last.rank
    end

    it 'refuses a step from another board' do
      foreign_step = create(:funnel_step, board: create(:funnel_board, account: account))

      expect { described_class.new(task: task, step: foreign_step).perform }
        .to raise_error(described_class::InvalidStep)
    end

    it 'records an audit event with the previous and the new position' do
      expect { described_class.new(task: task, step: target_step, actor: agent).perform }
        .to change(Funnel::TaskEvent, :count).by(1)

      event = Funnel::TaskEvent.last
      expect(event.event_type).to eq('task.moved')
      expect(event.data_before['step_id']).to eq(origin_step.id)
      expect(event.data_after['step_id']).to eq(target_step.id)
      expect(event.actor).to eq(agent)
    end

    it 'does not record an event when nothing actually changed' do
      expect { described_class.new(task: task, step: origin_step, actor: agent).perform }
        .not_to change(Funnel::TaskEvent, :count)
    end
  end

  describe 'rank exhaustion' do
    # Inserir sempre no mesmo intervalo divide o gap pela metade. O service rebalanceia a etapa
    # antes de a coluna decimal(30,15) perder a capacidade de representar o ponto medio.
    it 'keeps the order intact across many drops into the same gap' do
      above = create(:funnel_task, board_for_task: board, step: target_step)
      below = create(:funnel_task, board_for_task: board, step: target_step)

      30.times do
        dropped = create(:funnel_task, board_for_task: board, step: origin_step)
        described_class.new(task: dropped, step: target_step, after_id: above.id, before_id: below.id).perform
      end

      ranks = Funnel::Task.where(funnel_step_id: target_step.id).order(:rank).pluck(:rank)
      expect(ranks).to eq(ranks.sort)
      expect(ranks.uniq.size).to eq(ranks.size)
    end
  end
end
