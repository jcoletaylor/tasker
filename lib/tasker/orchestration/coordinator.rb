# frozen_string_literal: true

require_relative '../concerns/idempotent_state_transitions'
require_relative 'viable_step_discovery'
require_relative 'step_executor'
require_relative 'task_finalizer'
require_relative 'task_initializer'
require_relative 'step_sequence_factory'
require_relative 'task_reenqueuer'

module Tasker
  module Orchestration
    # Coordinator handles orchestration system initialization and monitoring
    #
    # This class ensures the orchestration system is properly initialized and provides
    # observability into the system state. It does NOT handle task processing -
    # that responsibility belongs to TaskHandler using the proven delegation pattern.
    class Coordinator
      include Tasker::Concerns::IdempotentStateTransitions

      class << self
        # Check if the orchestration system has been initialized
        #
        # @return [Boolean] True if initialized
        def initialized?
          @initialized == true
        end

        # Initialize the orchestration system
        #
        # Sets up all orchestration components, registers events, and connects subscribers.
        # This method is idempotent and can be called multiple times safely.
        def initialize!
          return if @initialized

          Rails.logger.info('Tasker::Orchestration::Coordinator: Initializing orchestration system')

          # Initialize core orchestration components
          setup_publisher
          setup_event_subscriptions

          # Initialize telemetry and monitoring
          setup_telemetry_subscriber

          @initialized = true
          Rails.logger.info('Tasker::Orchestration::Coordinator: Orchestration system initialized successfully')
        rescue StandardError => e
          Rails.logger.error("Tasker::Orchestration::Coordinator: Failed to initialize: #{e.message}")
          @initialized = false
          raise
        end

        # Reset initialization state (primarily for testing)
        def reset!
          @initialized = false
          @publisher = nil
          Rails.logger.debug('Tasker::Orchestration::Coordinator: Initialization state reset')
        end

        # Get statistics about the workflow orchestration system
        #
        # @return [Hash] Statistics about component initialization and event subscriptions
        def statistics
          {
            initialized: @initialized || false,
            components: {
              publisher: defined?(Tasker::Events::Publisher),
              viable_step_discovery: defined?(Tasker::Orchestration::ViableStepDiscovery),
              step_executor: defined?(Tasker::Orchestration::StepExecutor),
              task_finalizer: defined?(Tasker::Orchestration::TaskFinalizer),
              task_reenqueuer: defined?(Tasker::Orchestration::TaskReenqueuer)
            },
            publisher_instance: @publisher&.class&.name
          }
        end

        # Get sequence for a task (utility method for orchestration components)
        #
        # @param task [Tasker::Task] The task
        # @param task_handler [Object] The task handler
        # @return [Tasker::Types::StepSequence] The step sequence
        def get_sequence_for_task(task, task_handler)
          Tasker::Orchestration::StepSequenceFactory.get_sequence(task, task_handler)
        end

        private

        # Set up the main publisher
        def setup_publisher
          @publisher = Tasker::Events::Publisher.instance
        end

        # Set up event subscriptions for orchestration components
        def setup_event_subscriptions
          # Currently using direct method delegation instead of event subscriptions
          # for the core workflow loop. Events are used for observability.
          # Future enhancement: Add event-driven workflow subscriptions here
        end

        # Set up the telemetry subscriber for comprehensive observability
        def setup_telemetry_subscriber
          # Ensure telemetry subscriber is connected to the lifecycle events system

          if defined?(Tasker::Events::Subscribers::TelemetrySubscriber)
            Tasker::Events::Publisher.instance.tap do |publisher|
              Tasker::Events::Subscribers::TelemetrySubscriber.subscribe(publisher)
            end
            Rails.logger.debug('Tasker::Orchestration::Coordinator: TelemetrySubscriber connected successfully')
          else
            Rails.logger.debug('Tasker::Orchestration::Coordinator: TelemetrySubscriber not available')
          end
        rescue StandardError => e
          Rails.logger.error("Tasker::Orchestration::Coordinator: Failed to setup telemetry subscriber: #{e.message}")
        end
      end
    end
  end
end
