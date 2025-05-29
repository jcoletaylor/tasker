# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Orchestration::Coordinator do
  let(:mock_bus) { instance_double(Tasker::Events::Bus) }
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
    # Mock the event bus
    allow(Tasker::LifecycleEvents).to receive(:bus).and_return(mock_bus)
    allow(mock_bus).to receive(:present?).and_return(true)

    # Reset initialization state
    described_class.instance_variable_set(:@active, false)
  end

  describe '.initialize!' do
    it 'sets up all component subscriptions' do
      # Mock component subscription methods
      expect(Tasker::Orchestration::Orchestrator).to receive(:subscribe_to_state_events).with(mock_bus)
      expect(Tasker::Orchestration::ViableStepDiscovery).to receive(:subscribe_to_orchestration_events).with(mock_bus)
      expect(Tasker::Orchestration::StepExecutor).to receive(:subscribe_to_workflow_events).with(mock_bus)
      expect(Tasker::Orchestration::TaskFinalizer).to receive(:subscribe_to_workflow_events).with(mock_bus)

      described_class.initialize!(mock_bus)

      expect(described_class.active?).to be true
    end

    it 'uses default bus when none provided' do
      allow(Tasker::Orchestration::Orchestrator).to receive(:subscribe_to_state_events)
      allow(Tasker::Orchestration::ViableStepDiscovery).to receive(:subscribe_to_orchestration_events)
      allow(Tasker::Orchestration::StepExecutor).to receive(:subscribe_to_workflow_events)
      allow(Tasker::Orchestration::TaskFinalizer).to receive(:subscribe_to_workflow_events)

      described_class.initialize!

      expect(Tasker::LifecycleEvents).to have_received(:bus)
    end

    it 'logs initialization messages' do
      allow(Tasker::Orchestration::Orchestrator).to receive(:subscribe_to_state_events)
      allow(Tasker::Orchestration::ViableStepDiscovery).to receive(:subscribe_to_orchestration_events)
      allow(Tasker::Orchestration::StepExecutor).to receive(:subscribe_to_workflow_events)
      allow(Tasker::Orchestration::TaskFinalizer).to receive(:subscribe_to_workflow_events)

      expect(Rails.logger).to receive(:info).with(/Initializing event-driven workflow system/)
      expect(Rails.logger).to receive(:info).with(/initialized successfully/)

      described_class.initialize!(mock_bus)
    end
  end

  describe '.active?' do
    it 'returns false when not initialized' do
      expect(described_class.active?).to be false
    end

    it 'returns true after initialization' do
      allow(Tasker::Orchestration::Orchestrator).to receive(:subscribe_to_state_events)
      allow(Tasker::Orchestration::ViableStepDiscovery).to receive(:subscribe_to_orchestration_events)
      allow(Tasker::Orchestration::StepExecutor).to receive(:subscribe_to_workflow_events)
      allow(Tasker::Orchestration::TaskFinalizer).to receive(:subscribe_to_workflow_events)

      described_class.initialize!(mock_bus)

      expect(described_class.active?).to be true
    end
  end

  describe '.process_task' do
    context 'when not initialized' do
      it 'returns false and logs warning' do
        expect(Rails.logger).to receive(:warn).with(/System not initialized/)

        result = described_class.process_task(123)
        expect(result).to be false
      end
    end

    context 'when initialized' do
      before do
        allow(Tasker::Orchestration::Orchestrator).to receive(:subscribe_to_state_events)
        allow(Tasker::Orchestration::ViableStepDiscovery).to receive(:subscribe_to_orchestration_events)
        allow(Tasker::Orchestration::StepExecutor).to receive(:subscribe_to_workflow_events)
        allow(Tasker::Orchestration::TaskFinalizer).to receive(:subscribe_to_workflow_events)

        described_class.initialize!(mock_bus)
      end

      it 'finds task and transitions to in_progress' do
        allow(Tasker::Task).to receive(:find).with(123).and_return(task_double)
        allow(task_double).to receive(:state_machine).and_return(state_machine_double)
        expect(state_machine_double).to receive(:transition_to!).with(
          Tasker::Constants::TaskStatuses::IN_PROGRESS
        )

        result = described_class.process_task(123)
        expect(result).to be true
      end

      it 'logs processing start message' do
        allow(Tasker::Task).to receive(:find).with(123).and_return(task_double)
        allow(task_double).to receive(:state_machine).and_return(state_machine_double)
        allow(state_machine_double).to receive(:transition_to!)

        expect(Rails.logger).to receive(:info).with(/Starting event-driven processing for task 123/)

        described_class.process_task(123)
      end

      it 'handles errors gracefully' do
        allow(Tasker::Task).to receive(:find).and_raise(StandardError.new('Test error'))

        expect(Rails.logger).to receive(:error).with(/Error processing task 123/)

        result = described_class.process_task(123)
        expect(result).to be false
      end
    end
  end

  describe '.statistics' do
    it 'returns comprehensive statistics' do
      stats = described_class.statistics

      expect(stats).to be_a(Hash)
      expect(stats).to have_key(:initialized)
      expect(stats).to have_key(:components)
      expect(stats).to have_key(:event_bus_active)

      expect(stats[:components]).to have_key(:orchestrator)
      expect(stats[:components]).to have_key(:viable_step_discovery)
      expect(stats[:components]).to have_key(:step_executor)
      expect(stats[:components]).to have_key(:task_finalizer)
    end

    it 'shows correct initialization status' do
      stats_before = described_class.statistics
      expect(stats_before[:initialized]).to be false

      allow(Tasker::Orchestration::Orchestrator).to receive(:subscribe_to_state_events)
      allow(Tasker::Orchestration::ViableStepDiscovery).to receive(:subscribe_to_orchestration_events)
      allow(Tasker::Orchestration::StepExecutor).to receive(:subscribe_to_workflow_events)
      allow(Tasker::Orchestration::TaskFinalizer).to receive(:subscribe_to_workflow_events)

      described_class.initialize!(mock_bus)

      stats_after = described_class.statistics
      expect(stats_after[:initialized]).to be true
    end
  end

  describe 'integration flow' do
    let(:event_callbacks) { {} }

    before do
      # Mock event subscriptions to capture callbacks
      allow(mock_bus).to receive(:subscribe) do |event_name, &block|
        event_callbacks[event_name] = block
      end

      allow(Tasker::Orchestration::Orchestrator).to receive(:subscribe_to_state_events) do |bus|
        # Simulate Orchestrator subscription
        orchestrator = Tasker::Orchestration::Orchestrator.new
        bus.subscribe('task.start_requested') { |event| orchestrator.handle_task_started(event) }
      end

      allow(Tasker::Orchestration::ViableStepDiscovery).to receive(:subscribe_to_orchestration_events) do |bus|
        # Simulate ViableStepDiscovery subscription
        discovery = Tasker::Orchestration::ViableStepDiscovery.new
        bus.subscribe('workflow.task_started') { |event| discovery.discover_viable_steps_for_task(event[:task_id]) }
      end

      allow(Tasker::Orchestration::StepExecutor).to receive(:subscribe_to_workflow_events) do |bus|
        # Simulate StepExecutor subscription
        executor = Tasker::Orchestration::StepExecutor.new
        bus.subscribe('workflow.viable_steps_discovered') { |event| executor.execute_viable_steps(event) }
      end

      allow(Tasker::Orchestration::TaskFinalizer).to receive(:subscribe_to_workflow_events) do |bus|
        # Simulate TaskFinalizer subscription
        finalizer = Tasker::Orchestration::TaskFinalizer.new
        bus.subscribe('workflow.no_viable_steps') { |event| finalizer.finalize_task(event[:task_id]) }
      end
    end

    it 'successfully initializes all components' do
      expect { described_class.initialize!(mock_bus) }.not_to raise_error
      expect(described_class.active?).to be true
    end

    it 'components are available for instantiation' do
      described_class.initialize!(mock_bus)

      expect(Tasker::Orchestration::Orchestrator.new).to be_a(Tasker::Orchestration::Orchestrator)
      expect(Tasker::Orchestration::ViableStepDiscovery.new).to be_a(Tasker::Orchestration::ViableStepDiscovery)
      expect(Tasker::Orchestration::StepExecutor.new).to be_a(Tasker::Orchestration::StepExecutor)
      expect(Tasker::Orchestration::TaskFinalizer.new).to be_a(Tasker::Orchestration::TaskFinalizer)
    end
  end
end
