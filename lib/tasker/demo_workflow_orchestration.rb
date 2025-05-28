# frozen_string_literal: true

module Tasker
  # Demo script for the new event-driven workflow orchestration system
  #
  # This demonstrates how to initialize and use the declarative workflow system
  # that replaces the imperative TaskHandler loop.
  class DemoWorkflowOrchestration
    def self.run_demo
      Rails.logger.debug '🚀 Tasker Event-Driven Workflow Orchestration Demo'
      Rails.logger.debug '=' * 60

      # Step 1: Initialize the event-driven workflow system
      Rails.logger.debug "\n📋 Step 1: Initializing event-driven workflow system..."
      Tasker::WorkflowOrchestration.initialize!

      # Show statistics
      stats = Tasker::WorkflowOrchestration.statistics
      Rails.logger.debug { "✅ System initialized: #{stats[:initialized]}" }
      Rails.logger.debug '📊 Components loaded:'
      stats[:components].each do |component, loaded|
        Rails.logger.debug "   - #{component}: #{loaded ? '✅' : '❌'}"
      end

      # Step 2: Show the difference from imperative workflow
      Rails.logger.debug "\n📋 Step 2: How it works vs. imperative approach"
      Rails.logger.debug "\n🔴 OLD WAY (Imperative):"
      Rails.logger.debug { <<~OLD_WAY }
        # TaskHandler::InstanceMethods#handle method
        loop do
          task.reload
          sequence = get_sequence(task)
          viable_steps = find_viable_steps(task, sequence)
          break if viable_steps.empty?
          processed_steps = handle_viable_steps(task, sequence, viable_steps)
          break if blocked_by_errors?(task, sequence, processed_steps)
        end
        finalize(task, final_sequence, all_processed_steps)
      OLD_WAY

      Rails.logger.debug "\n🟢 NEW WAY (Event-Driven):"
      Rails.logger.debug { <<~NEW_WAY }
        # Just trigger the initial state transition:
        task.state_machine.transition_to!(Constants::TaskStatuses::IN_PROGRESS)

        # The rest happens automatically via events:
        # 1. TaskStateMachine fires 'task.start_requested' event
        # 2. WorkflowOrchestrator handles it, publishes 'workflow.task_started'
        # 3. ViableStepDiscovery finds steps, publishes 'workflow.viable_steps_discovered'
        # 4. StepExecutor executes steps, which fire completion events
        # 5. Events cascade until TaskFinalizer completes the task
      NEW_WAY

      # Step 3: Show the event flow
      Rails.logger.debug "\n📋 Step 3: Event-driven workflow flow"
      Rails.logger.debug { <<~FLOW }

        🔄 Event Flow Architecture:

        State Machine Events        Workflow Orchestration Events
        ────────────────────       ──────────────────────────────
        task.start_requested   →   workflow.task_started
        step.completed         →   workflow.step_completed
                              →   workflow.orchestration_requested
                              →   workflow.viable_steps_discovered
                              →   workflow.steps_execution_started
                              →   workflow.no_viable_steps
                              →   workflow.task_finalization_started

        🎯 Components & Responsibilities:

        1. WorkflowOrchestrator:  Listens to state events, coordinates workflow
        2. ViableStepDiscovery:   Finds executable steps based on dependencies
        3. StepExecutor:          Executes steps via state machine transitions
        4. TaskFinalizer:         Determines task completion and cleanup

        🔧 State Machines:

        - TaskStateMachine:   Manages task lifecycle (pending → in_progress → complete)
        - StepStateMachine:   Manages step execution with automatic retry logic
      FLOW

      # Step 4: Usage example
      Rails.logger.debug "\n📋 Step 4: Usage example"
      Rails.logger.debug { <<~USAGE }

        🚀 How to process a task with the new system:

        # Initialize the workflow orchestration (do this once at startup)
        Tasker::WorkflowOrchestration.initialize!

        # Process a task (replaces TaskHandler.handle)
        success = Tasker::WorkflowOrchestration.process_task(task_id)

        # That's it! The event-driven system handles:
        # ✅ Step dependency resolution
        # ✅ Concurrent/sequential execution
        # ✅ Error handling and retries
        # ✅ Task completion detection
        # ✅ Comprehensive telemetry
      USAGE

      # Step 5: Benefits
      Rails.logger.debug "\n📋 Step 5: Benefits of the new system"
      Rails.logger.debug { <<~BENEFITS }

        🎯 Key Benefits:

        ✅ Declarative:     Steps declare what events they respond to
        ✅ Testable:        Each component can be tested in isolation
        ✅ Extensible:      Easy to add new behaviors via event subscribers
        ✅ Observable:      Rich event stream for debugging and monitoring
        ✅ Concurrent-Safe: State machines handle race conditions
        ✅ Audit Trail:     Complete history of all state transitions
        ✅ Less Complex:    ~500 lines of imperative logic → clean event handlers

        🔍 Debugging: Check the event logs to understand workflow progression
        📊 Monitoring: Subscribe to events for real-time workflow metrics
        🛠️  Extending: Add new functionality by subscribing to events
      BENEFITS

      Rails.logger.debug "\n🎉 Demo complete! The event-driven workflow system is ready to use."
      Rails.logger.debug '💡 Try: Tasker::WorkflowOrchestration.process_task(your_task_id)'
    end

    # Demo of adding a custom event subscriber
    def self.demo_custom_subscriber
      Rails.logger.debug "\n🔧 Demo: Adding a custom event subscriber"

      # Example custom subscriber for workflow monitoring
      custom_subscriber = Class.new do
        def self.subscribe(bus)
          bus.subscribe('workflow.task_started') do |event|
            Rails.logger.debug "🏁 Custom Monitor: Task #{event[:task_id]} started at #{event[:orchestrated_at]}"
          end

          bus.subscribe('workflow.viable_steps_discovered') do |event|
            Rails.logger.debug "🔍 Custom Monitor: Found #{event[:count]} viable steps for task #{event[:task_id]}"
          end

          bus.subscribe('workflow.task_finalization_completed') do |event|
            Rails.logger.debug "🏆 Custom Monitor: Task #{event[:task_id]} finalized with status: #{event[:final_state]}"
          end
        end
      end

      # Subscribe the custom subscriber
      Tasker::LifecycleEvents.subscribe_object(custom_subscriber)

      Rails.logger.debug '✅ Custom subscriber added! It will now monitor workflow events.'
    end
  end
end
