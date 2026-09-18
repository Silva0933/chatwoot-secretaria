require 'rails_helper'

RSpec.describe Funnel::Automations::Runner do
  let!(:account) { create(:account) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:board) { create(:funnel_board, account: account) }
  let!(:entry) { create(:funnel_step, board: board, name: 'Novo', stage_type: :open, rank: 100) }
  let!(:won_step) { create(:funnel_step, board: board, name: 'Ganho', stage_type: :won, rank: 200) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox) }

  def enable(*rules)
    board.update!(automation_settings: rules.index_with { true })
  end

  def run(rule, event_name: 'conversation.created', task: nil)
    described_class.new(board: board.reload, event_name: event_name, conversation: conversation, task: task).call(rule)
  end

  describe 'the enable switch' do
    it 'does nothing when the rule is off' do
      expect { run('create_task_on_conversation') }.not_to change(Funnel::Task, :count)
    end

    it 'records nothing when the rule is off' do
      expect { run('create_task_on_conversation') }.not_to change(Funnel::AutomationRun, :count)
    end

    it 'ignores a rule name it does not know' do
      enable('create_task_on_conversation')

      expect { run('drop_database') }.not_to change(Funnel::AutomationRun, :count)
    end
  end

  describe 'create_task_on_conversation' do
    before { enable('create_task_on_conversation') }

    it 'creates the card and links the conversation as primary' do
      expect { run('create_task_on_conversation') }.to change(Funnel::Task, :count).by(1)

      task = Funnel::Task.last
      expect(task.task_conversations.sole).to have_attributes(conversation_id: conversation.id, is_primary: true)
      expect(task.funnel_step_id).to eq(entry.id)
    end

    it 'does not create a second card for the same conversation' do
      run('create_task_on_conversation')

      expect { run('create_task_on_conversation') }.not_to change(Funnel::Task, :count)
    end
  end

  describe 'auto_assign_task' do
    before { enable('create_task_on_conversation', 'auto_assign_task') }

    it 'puts whoever handles the conversation on the card' do
      conversation.update!(assignee: agent)
      run('create_task_on_conversation')

      run('auto_assign_task')

      expect(Funnel::Task.last.assignees).to contain_exactly(agent)
    end

    it 'does nothing while the conversation has no assignee' do
      run('create_task_on_conversation')

      run('auto_assign_task')

      expect(Funnel::Task.last.assignees).to be_empty
    end
  end

  describe 'win_task_on_conversation_resolved' do
    before { enable('create_task_on_conversation', 'win_task_on_conversation_resolved') }

    it 'moves the card to the won stage' do
      run('create_task_on_conversation')

      run('win_task_on_conversation_resolved', event_name: 'conversation.resolved')

      expect(Funnel::Task.last.funnel_step_id).to eq(won_step.id)
    end

    # Sem etapa de ganho o quadro nao tem para onde mover; falhar seria pior que nao fazer nada.
    it 'reports that the board has no won stage instead of raising' do
      won_step.destroy!
      run('create_task_on_conversation')

      run('win_task_on_conversation_resolved', event_name: 'conversation.resolved')

      run_row = Funnel::AutomationRun.where(rule: 'win_task_on_conversation_resolved').last
      expect(run_row.status).to eq('ok')
      expect(run_row.data['result']).to include('no won stage')
    end
  end

  describe 'resolve_conversation_on_final_step' do
    before { enable('create_task_on_conversation', 'resolve_conversation_on_final_step') }

    it 'resolves the conversation when the card lands on a closing stage' do
      run('create_task_on_conversation')
      task = Funnel::Task.last
      task.update!(funnel_step_id: won_step.id)

      run('resolve_conversation_on_final_step', event_name: 'funnel.task.moved', task: task.reload)

      expect(conversation.reload).to be_resolved
    end

    it 'leaves the conversation alone while the card is on an open stage' do
      run('create_task_on_conversation')

      run('resolve_conversation_on_final_step', event_name: 'funnel.task.moved', task: Funnel::Task.last)

      expect(conversation.reload).not_to be_resolved
    end
  end

  # O risco central do modulo: sincronizar responsavel nos dois sentidos faz a mudanca no card
  # disparar a da conversa, que dispara a do card, para sempre.
  describe 'loop protection' do
    before { enable('create_task_on_conversation', 'sync_assignees') }

    it 'refuses to run an automation from inside another one' do
      described_class.with_guard do
        expect { run('create_task_on_conversation') }.not_to change(Funnel::Task, :count)
      end
    end

    it 'runs again normally once the outer automation finished' do
      described_class.with_guard { nil }

      expect { run('create_task_on_conversation') }.to change(Funnel::Task, :count).by(1)
    end

    it 'clears the guard even when the automation raises' do
      allow(Funnel::Task).to receive(:new).and_raise(StandardError, 'boom')
      run('create_task_on_conversation')

      expect(described_class).not_to be_running
    end
  end

  describe 'failure handling' do
    before { enable('create_task_on_conversation') }

    # Uma automacao que falha nao pode derrubar a acao que a disparou.
    it 'swallows the error and records it' do
      allow(Funnel::Task).to receive(:new).and_raise(StandardError, 'boom')

      expect { run('create_task_on_conversation') }.not_to raise_error

      row = Funnel::AutomationRun.last
      expect(row.status).to eq('error')
      expect(row.error).to include('boom')
    end
  end

  describe 'the audit trail' do
    before { enable('create_task_on_conversation') }

    it 'records the rule, the event and what happened' do
      run('create_task_on_conversation')

      row = Funnel::AutomationRun.last
      expect(row).to have_attributes(
        rule: 'create_task_on_conversation',
        event_name: 'conversation.created',
        status: 'ok',
        conversation_id: conversation.id,
        funnel_board_id: board.id
      )
      expect(row.data['result']).to include('created task')
    end
  end
end
