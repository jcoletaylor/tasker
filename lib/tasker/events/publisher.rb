# frozen_string_literal: true

require 'dry/events'
require 'singleton'
require_relative '../concerns/idempotent_state_transitions'

module Tasker
  module Events
    # Core event infrastructure for the Tasker system
    #
    # This publisher provides the core event infrastructure using dry-events.
    # It handles event registration and basic publishing capabilities.
    #
    # For application usage, use the EventPublisher concern which provides
    # clean domain-specific methods that build standardized payloads:
    #
    #   include Tasker::Concerns::EventPublisher
    #   publish_step_completed(step, additional_context: {...})
    #   publish_task_failed(task, error_message: "...")
    class Publisher
      include Dry::Events::Publisher[:tasker]
      include Tasker::Concerns::IdempotentStateTransitions
      include Singleton

      def initialize
        # Register all events during initialization
        register_all_events
        register_state_machine_events
        register_workflow_events
        register_test_events if Rails.env.local?
      end

      # Core publish method with automatic timestamp enhancement
      #
      # This is the primary method used by the EventPublisher concern.
      # Applications should use the EventPublisher concern methods instead
      # of calling this directly.
      #
      # @param event_name [String] The event name
      # @param payload [Hash] The event payload
      # @return [void]
      def publish(event_name, payload = {})
        # Ensure timestamp is always present in the payload
        enhanced_payload = {
          timestamp: Time.current
        }.merge(payload)

        # Call the parent publish method
        super(event_name, enhanced_payload)
      end

      private

      # Register all standard Tasker events
      def register_all_events
        # Register task events
        register_event(Tasker::Constants::TaskEvents::INITIALIZE_REQUESTED)
        register_event(Tasker::Constants::TaskEvents::START_REQUESTED)
        register_event(Tasker::Constants::TaskEvents::COMPLETED)
        register_event(Tasker::Constants::TaskEvents::FAILED)
        register_event(Tasker::Constants::TaskEvents::CANCELLED)
        register_event(Tasker::Constants::TaskEvents::RETRY_REQUESTED)

        # Register step events
        register_event(Tasker::Constants::StepEvents::INITIALIZE_REQUESTED)
        register_event(Tasker::Constants::StepEvents::EXECUTION_REQUESTED)
        register_event(Tasker::Constants::StepEvents::COMPLETED)
        register_event(Tasker::Constants::StepEvents::FAILED)
        register_event(Tasker::Constants::StepEvents::RETRY_REQUESTED)
        register_event(Tasker::Constants::StepEvents::CANCELLED)
        register_event(Tasker::Constants::StepEvents::BEFORE_HANDLE)
        register_event(Tasker::Constants::StepEvents::HANDLE)

        # Register observability events for telemetry
        register_event(Tasker::Constants::ObservabilityEvents::Task::HANDLE)
        register_event(Tasker::Constants::ObservabilityEvents::Task::ENQUEUE)
        register_event(Tasker::Constants::ObservabilityEvents::Task::FINALIZE)
        register_event(Tasker::Constants::ObservabilityEvents::Step::FIND_VIABLE)
        register_event(Tasker::Constants::ObservabilityEvents::Step::HANDLE)
        register_event(Tasker::Constants::ObservabilityEvents::Step::BACKOFF)
        register_event(Tasker::Constants::ObservabilityEvents::Step::SKIP)
        register_event(Tasker::Constants::ObservabilityEvents::Step::MAX_RETRIES_REACHED)
      end

      # Register state machine transition events
      def register_state_machine_events
        register_event(Tasker::Constants::TaskEvents::BEFORE_TRANSITION)
        register_event(Tasker::Constants::TaskEvents::RESOLVED_MANUALLY)

        register_event(Tasker::Constants::StepEvents::BEFORE_TRANSITION)
      end

      # Register workflow orchestration events
      def register_workflow_events
        # Task lifecycle events
        register_event(Tasker::Constants::WorkflowEvents::TASK_STARTED)
        register_event(Tasker::Constants::WorkflowEvents::TASK_COMPLETED)
        register_event(Tasker::Constants::WorkflowEvents::TASK_FAILED)
        register_event(Tasker::Constants::WorkflowEvents::TASK_REENQUEUE_STARTED)
        register_event(Tasker::Constants::WorkflowEvents::TASK_REENQUEUE_REQUESTED)
        register_event(Tasker::Constants::WorkflowEvents::TASK_REENQUEUE_FAILED)
        register_event(Tasker::Constants::WorkflowEvents::TASK_REENQUEUE_DELAYED)
        register_event(Tasker::Constants::WorkflowEvents::TASK_STATE_UNCLEAR)

        # Step lifecycle events
        register_event(Tasker::Constants::WorkflowEvents::STEP_COMPLETED)
        register_event(Tasker::Constants::WorkflowEvents::STEP_FAILED)
        register_event(Tasker::Constants::WorkflowEvents::STEP_EXECUTION_FAILED)

        # Workflow discovery and orchestration events
        register_event(Tasker::Constants::WorkflowEvents::ORCHESTRATION_REQUESTED)
        register_event(Tasker::Constants::WorkflowEvents::VIABLE_STEPS_DISCOVERED)
        register_event(Tasker::Constants::WorkflowEvents::VIABLE_STEPS_BATCH_READY)
        register_event(Tasker::Constants::WorkflowEvents::STEPS_EXECUTION_STARTED)
        register_event(Tasker::Constants::WorkflowEvents::STEPS_EXECUTION_COMPLETED)
        register_event(Tasker::Constants::WorkflowEvents::NO_VIABLE_STEPS)

        # Task finalization events
        register_event(Tasker::Constants::WorkflowEvents::TASK_FINALIZATION_STARTED)
        register_event(Tasker::Constants::WorkflowEvents::TASK_FINALIZATION_COMPLETED)
      end

      # Register test events for testing
      def register_test_events
        # Register test events - fail hard if constants don't exist
        register_event(Tasker::Constants::TestEvents::BASIC_EVENT)
        register_event(Tasker::Constants::TestEvents::SLOW_EVENT)
        register_event(Tasker::Constants::TestEvents::TEST_EVENT)

        # Also register common test event patterns
        register_event('Test.Event') # Common test event name
      end
    end
  end
end
