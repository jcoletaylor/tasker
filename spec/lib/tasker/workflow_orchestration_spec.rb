# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Orchestration::Coordinator do
  let(:task_double) do
    instance_double(
      Tasker::Task,
      task_id: 123,
      name: 'test_task',
      status: Tasker::Constants::TaskStatuses::PENDING
    )
  end
  let(:state_machine_double) { instance_double(Tasker::StateMachine::TaskStateMachine) }

  before do
    # Reset initialization state
    described_class.instance_variable_set(:@initialized, false)
  end

  describe '.initialize!' do
    it 'sets up all orchestration components' do
      expect { described_class.initialize! }.not_to raise_error
      expect(described_class.initialized?).to be true
    end

    it 'is idempotent and can be called multiple times safely' do
      described_class.initialize!
      expect(described_class.initialized?).to be true

      # Calling again should not cause errors
      expect { described_class.initialize! }.not_to raise_error
      expect(described_class.initialized?).to be true
    end
  end

  describe '.statistics' do
    before do
      described_class.initialize!
    end

    it 'provides statistics about orchestration components' do
      stats = described_class.statistics

      expect(stats).to include(
        initialized: true,
        components: hash_including(
          publisher: be_truthy,
          viable_step_discovery: be_truthy,
          step_executor: be_truthy,
          task_finalizer: be_truthy,
          task_reenqueuer: be_truthy
        )
      )
    end
  end
end
