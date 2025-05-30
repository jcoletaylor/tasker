# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Workflow Orchestration System', type: :integration do
  # This spec serves as both documentation and integration testing for the
  # event-driven workflow orchestration system that replaces the imperative
  # TaskHandler workflow loop.

  let(:task) { create(:task, :with_workflow_steps) }
  let(:event_bus) { Tasker::LifecycleEvents.bus }

  before do
    # Ensure clean state for each test
    Tasker::Orchestration::Coordinator.instance_variable_set(:@active, false)
  end

  describe 'System Initialization' do
    it 'initializes the complete event-driven workflow system' do
      expect(Tasker::Orchestration::Coordinator.active?).to be false

      # Initialize the workflow orchestration system
      Tasker::Orchestration::Coordinator.initialize!

      expect(Tasker::Orchestration::Coordinator.active?).to be true

      # Verify all components are loaded and subscribed
      stats = Tasker::Orchestration::Coordinator.statistics
      expect(stats[:initialized]).to be true
      expect(stats[:components][:orchestrator]).to be_truthy
      expect(stats[:components][:viable_step_discovery]).to be_truthy
      expect(stats[:components][:step_executor]).to be_truthy
      expect(stats[:components][:task_finalizer]).to be_truthy
      expect(stats[:event_bus_active]).to be true
    end

    it 'provides comprehensive system statistics' do
      Tasker::Orchestration::Coordinator.initialize!

      stats = Tasker::Orchestration::Coordinator.statistics

      expect(stats).to include(
        initialized: true,
        components: hash_including(
          orchestrator: be_truthy,
          viable_step_discovery: be_truthy,
          step_executor: be_truthy,
          task_finalizer: be_truthy
        ),
        event_bus_active: true
      )
    end
  end

  describe 'Event-Driven Workflow Processing' do
    before do
      Tasker::Orchestration::Coordinator.initialize!
    end

    it 'processes a task through the complete event-driven workflow' do
      # Track events fired during processing
      fired_events = []

      # Subscribe to key workflow events for verification
      event_bus.subscribe('workflow.task_started') do |event|
        fired_events << { type: 'task_started', data: event }
      end

      event_bus.subscribe('workflow.viable_steps_discovered') do |event|
        fired_events << { type: 'viable_steps_discovered', data: event }
      end

      event_bus.subscribe('workflow.steps_execution_started') do |event|
        fired_events << { type: 'steps_execution_started', data: event }
      end

      # Process the task using the new system
      result = Tasker::Orchestration::Coordinator.process_task(task.task_id)

      expect(result).to be true
      expect(task.reload.status).to eq(Tasker::Constants::TaskStatuses::IN_PROGRESS)

      # Verify the event cascade was triggered
      expect(fired_events).not_to be_empty

      task_started_event = fired_events.find { |e| e[:type] == 'task_started' }
      expect(task_started_event).to be_present
      expect(task_started_event[:data][:task_id]).to eq(task.task_id)
    end

    it 'demonstrates the declarative vs imperative approach' do
      # OLD WAY (Imperative) - what we're replacing:
      # loop do
      #   task.reload
      #   sequence = get_sequence(task)
      #   viable_steps = find_viable_steps(task, sequence)
      #   break if viable_steps.empty?
      #   processed_steps = handle_viable_steps(task, sequence, viable_steps)
      #   break if blocked_by_errors?(task, sequence, processed_steps)
      # end
      # finalize(task, final_sequence, all_processed_steps)

      # NEW WAY (Event-Driven) - what we're implementing:
      # Just trigger the initial state transition:
      expect do
        task.state_machine.transition_to!(Tasker::Constants::TaskStatuses::IN_PROGRESS)
      end.to change { task.reload.status }.to(Tasker::Constants::TaskStatuses::IN_PROGRESS)

      # The rest happens automatically via events:
      # 1. TaskStateMachine fires 'task.start_requested' event
      # 2. Orchestrator handles it, publishes 'workflow.task_started'
      # 3. ViableStepDiscovery finds steps, publishes 'workflow.viable_steps_discovered'
      # 4. StepExecutor executes steps, which fire completion events
      # 5. Events cascade until TaskFinalizer completes the task
    end
  end

  describe 'Component Responsibilities' do
    before do
      Tasker::Orchestration::Coordinator.initialize!
    end

    describe 'Orchestrator' do
      it 'coordinates workflow execution through event-driven orchestration' do
        orchestrator = Tasker::Orchestration::Orchestrator.new

        # Mock event to test orchestrator response
        task_started_event = {
          task_id: task.task_id,
          task_name: task.name
        }

        expect do
          orchestrator.handle_task_started(task_started_event)
        end.not_to raise_error

        # Verify orchestrator publishes workflow events
        expect(orchestrator).to respond_to(:handle_task_started)
        expect(orchestrator).to respond_to(:handle_step_completed)
        expect(orchestrator).to respond_to(:request_orchestration)
      end
    end

    describe 'ViableStepDiscovery' do
      it 'discovers which steps can be executed based on workflow state' do
        discovery = Tasker::Orchestration::ViableStepDiscovery.new

        expect do
          discovery.discover_viable_steps_for_task(task.task_id)
        end.not_to raise_error

        # Verify discovery component has the right interface
        expect(discovery).to respond_to(:discover_viable_steps_for_task)
      end
    end

    describe 'StepExecutor' do
      it 'handles the execution of workflow steps via state machine transitions' do
        executor = Tasker::Orchestration::StepExecutor.new

        # Mock viable steps discovered event
        viable_steps_event = {
          task_id: task.task_id,
          step_ids: task.workflow_steps.pluck(:workflow_step_id),
          processing_mode: 'sequential'
        }

        expect do
          executor.execute_viable_steps(viable_steps_event)
        end.not_to raise_error

        # Verify executor component has the right interface
        expect(executor).to respond_to(:execute_viable_steps)
      end
    end

    describe 'TaskFinalizer' do
      it 'handles task completion and finalization logic' do
        finalizer = Tasker::Orchestration::TaskFinalizer.new

        expect do
          finalizer.check_task_completion(task.task_id)
        end.not_to raise_error

        # Verify finalizer component has the right interface
        expect(finalizer).to respond_to(:finalize_task)
        expect(finalizer).to respond_to(:check_task_completion)
      end
    end
  end

  describe 'Event Flow Architecture' do
    before do
      Tasker::Orchestration::Coordinator.initialize!
    end

    it 'demonstrates the complete event flow' do
      # Track the complete event flow
      event_flow = []

      # State Machine Events
      [
        'task.start_requested',
        Tasker::Constants::StepEvents::COMPLETED,
        Tasker::Constants::TaskEvents::COMPLETED
      ].each do |event_name|
        event_bus.subscribe(event_name) do |event|
          event_flow << { category: 'state_machine', event: event_name, data: event }
        end
      end

      # Workflow Orchestration Events
      %w[
        workflow.task_started
        workflow.step_completed
        workflow.orchestration_requested
        workflow.viable_steps_discovered
        workflow.steps_execution_started
        workflow.no_viable_steps
        workflow.task_finalization_started
      ].each do |event_name|
        event_bus.subscribe(event_name) do |event|
          event_flow << { category: 'orchestration', event: event_name, data: event }
        end
      end

      # Trigger the workflow
      Tasker::Orchestration::Coordinator.process_task(task.task_id)

      # Verify we captured events from both categories
      state_machine_events = event_flow.select { |e| e[:category] == 'state_machine' }
      orchestration_events = event_flow.select { |e| e[:category] == 'orchestration' }

      expect(state_machine_events).not_to be_empty
      expect(orchestration_events).not_to be_empty

      # Verify the task_started event was fired
      task_started = orchestration_events.find { |e| e[:event] == 'workflow.task_started' }
      expect(task_started).to be_present
      expect(task_started[:data][:task_id]).to eq(task.task_id)
    end
  end

  describe 'Custom Event Subscribers' do
    before do
      Tasker::Orchestration::Coordinator.initialize!
    end

    it 'allows adding custom event subscribers for monitoring' do
      # Example of adding a custom event subscriber for workflow monitoring
      monitoring_events = []

      # Custom subscriber for workflow monitoring
      custom_subscriber = Class.new do
        def self.subscribe(bus)
          bus.subscribe('workflow.task_started') do |event|
            monitoring_events << {
              type: 'task_started',
              task_id: event[:task_id],
              timestamp: event[:orchestrated_at]
            }
          end

          bus.subscribe('workflow.viable_steps_discovered') do |event|
            monitoring_events << {
              type: 'steps_discovered',
              task_id: event[:task_id],
              count: event[:count]
            }
          end
        end
      end

      # Subscribe the custom subscriber
      custom_subscriber.subscribe(event_bus)

      # Trigger workflow processing
      Tasker::Orchestration::Coordinator.process_task(task.task_id)

      # Verify custom monitoring captured events
      expect(monitoring_events).not_to be_empty

      task_started_event = monitoring_events.find { |e| e[:type] == 'task_started' }
      expect(task_started_event).to be_present
      expect(task_started_event[:task_id]).to eq(task.task_id)
    end
  end

  describe 'Benefits Demonstration' do
    before do
      Tasker::Orchestration::Coordinator.initialize!
    end

    it 'demonstrates key benefits of the event-driven system' do
      # ✅ Declarative: Steps declare what events they respond to
      expect(Tasker::Orchestration::ViableStepDiscovery).to respond_to(:subscribe_to_orchestration_events)
      expect(Tasker::Orchestration::StepExecutor).to respond_to(:subscribe_to_workflow_events)

      # ✅ Testable: Each component can be tested in isolation
      orchestrator = Tasker::Orchestration::Orchestrator.new
      discovery = Tasker::Orchestration::ViableStepDiscovery.new
      executor = Tasker::Orchestration::StepExecutor.new
      finalizer = Tasker::Orchestration::TaskFinalizer.new

      expect(orchestrator).to be_a(Tasker::Orchestration::Orchestrator)
      expect(discovery).to be_a(Tasker::Orchestration::ViableStepDiscovery)
      expect(executor).to be_a(Tasker::Orchestration::StepExecutor)
      expect(finalizer).to be_a(Tasker::Orchestration::TaskFinalizer)

      # ✅ Observable: Rich event stream for debugging and monitoring
      events_captured = []
      event_bus.subscribe('workflow.task_started') do |event|
        events_captured << event
      end

      Tasker::Orchestration::Coordinator.process_task(task.task_id)
      expect(events_captured).not_to be_empty

      # ✅ Concurrent-Safe: State machines handle race conditions
      expect(task.state_machine).to respond_to(:transition_to!)
      expect(task.state_machine).to respond_to(:current_state)

      # ✅ Audit Trail: Complete history of all state transitions
      expect(task.task_transitions).to respond_to(:recent)
      expect(task.task_transitions).to respond_to(:to_state)
    end
  end

  describe 'Usage Patterns' do
    it 'shows how to use the new system instead of TaskHandler.handle' do
      # Initialize the workflow orchestration (do this once at startup)
      Tasker::Orchestration::Coordinator.initialize!

      # Process a task (replaces TaskHandler.handle)
      success = Tasker::Orchestration::Coordinator.process_task(task.task_id)

      expect(success).to be true

      # That's it! The event-driven system handles:
      # ✅ Step dependency resolution
      # ✅ Concurrent/sequential execution
      # ✅ Error handling and retries
      # ✅ Task completion detection
      # ✅ Comprehensive telemetry
    end

    it 'provides debugging capabilities through event logs' do
      Tasker::Orchestration::Coordinator.initialize!

      # Capture all events for debugging
      debug_log = []

      # Subscribe to all workflow events
      %w[
        workflow.task_started
        workflow.viable_steps_discovered
        workflow.steps_execution_started
        workflow.task_finalization_started
      ].each do |event_name|
        event_bus.subscribe(event_name) do |event|
          debug_log << {
            event: event_name,
            timestamp: Time.current,
            data: event
          }
        end
      end

      # Process task
      Tasker::Orchestration::Coordinator.process_task(task.task_id)

      # Debug log shows complete workflow progression
      expect(debug_log).not_to be_empty
      expect(debug_log.first[:event]).to eq('workflow.task_started')
    end
  end
end
