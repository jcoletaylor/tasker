# frozen_string_literal: true

require_relative 'orchestrator'
require_relative 'viable_step_discovery'
require_relative 'step_executor'
require_relative 'task_finalizer'

module Tasker
  module Orchestration
    # Coordinator manages the setup and initialization of the event-driven workflow system
    #
    # This module provides the main entry point for initializing the declarative workflow orchestration
    # that replaces the imperative TaskHandler workflow loop.
    module Coordinator
      class << self
        # Include the concern methods at the class level
        include Tasker::Concerns::IdempotentStateTransitions

        # Initialize the complete workflow orchestration system
        #
        # This sets up all event subscriptions and coordinates the components:
        # - Orchestrator: Handles state transition events
        # - ViableStepDiscovery: Discovers which steps can be executed
        # - StepExecutor: Executes viable steps
        # - TaskFinalizer: Handles task completion and finalization
        #
        # @param event_bus [Tasker::Events::Bus] Optional event bus instance
        def initialize!(event_bus = nil)
          # Prevent double initialization
          return if @initialized

          Rails.logger.info('Tasker::Orchestration::Coordinator: Initializing event-driven workflow system')

          # Use provided bus or default
          bus = event_bus || Tasker::LifecycleEvents.bus

          # Subscribe all workflow components to their respective events
          setup_component_subscriptions(bus)

          @initialized = true

          Rails.logger.info('Tasker::Orchestration::Coordinator: Event-driven workflow system initialized successfully')
        end

        # Check if the system has been initialized
        #
        # @return [Boolean] True if initialized
        def initialized?
          @initialized || false
        end

        # Trigger workflow orchestration for a specific task
        #
        # This is the main entry point for starting workflow processing using the event-driven system
        # instead of the imperative TaskHandler.handle method.
        #
        # @param task_id [Integer] The task ID to process
        # @return [Boolean] True if processing started successfully, false if failed
        def process_task(task_id)
          Rails.logger.info("Tasker::Orchestration::Coordinator: Starting event-driven processing for task #{task_id}")

          # Load the task and transition it to in_progress, which will trigger the orchestration
          task = Tasker::Task.find(task_id)

          # Use the concern's safe_transition_to method
          transition_result = safe_transition_to(task, Constants::TaskStatuses::IN_PROGRESS)

          Rails.logger.debug("Tasker::Orchestration::Coordinator: Task #{task_id} transition result: #{transition_result}")

          # The orchestration system is now event-driven and asynchronous
          # The task will be processed through events, and if it needs reenqueuing,
          # that will happen via TaskFinalizer which is terminal for this execution

          # Return true to indicate we successfully started orchestration
          # The actual completion/reenqueuing happens asynchronously through events
          true
        rescue StandardError => e
          Rails.logger.error("Tasker::Orchestration::Coordinator: Error processing task #{task_id}: #{e.message}")
          false
        end

        # Get statistics about the workflow orchestration system
        #
        # @return [Hash] Statistics about component initialization and event subscriptions
        def statistics
          {
            initialized: @initialized || false,
            components: {
              orchestrator: defined?(Tasker::Orchestration::Orchestrator),
              viable_step_discovery: defined?(Tasker::Orchestration::ViableStepDiscovery),
              step_executor: defined?(Tasker::Orchestration::StepExecutor),
              task_finalizer: defined?(Tasker::Orchestration::TaskFinalizer)
            },
            event_bus_active: defined?(Tasker::LifecycleEvents) && Tasker::LifecycleEvents.bus.present?
          }
        end

        private

        # Set up event subscriptions for all workflow components
        #
        # @param bus [Tasker::Events::Bus] The event bus to use for subscriptions
        def setup_component_subscriptions(bus)
          # Subscribe Orchestrator to state transition events
          Tasker::Orchestration::Orchestrator.subscribe_to_state_events(bus)

          # Subscribe ViableStepDiscovery to orchestration events
          Tasker::Orchestration::ViableStepDiscovery.subscribe_to_orchestration_events(bus)

          # Subscribe StepExecutor to workflow events
          Tasker::Orchestration::StepExecutor.subscribe_to_workflow_events(bus)

          # Subscribe TaskFinalizer to workflow events
          Tasker::Orchestration::TaskFinalizer.subscribe_to_workflow_events(bus)
        end
      end
    end
  end
end
