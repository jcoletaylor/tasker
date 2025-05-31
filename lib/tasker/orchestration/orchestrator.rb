# frozen_string_literal: true

require 'dry/events'
require_relative '../concerns/idempotent_state_transitions'
require 'tasker/events/event_payload_builder'

module Tasker
  module Orchestration
    # Orchestrator provides event publishing capabilities for workflow observability
    #
    # This class is primarily used for publishing lifecycle events that can be
    # observed by telemetry and monitoring systems. The actual workflow control
    # uses direct method delegation for reliability.
    class Orchestrator
      include Dry::Events::Publisher[:workflow]
      include Tasker::Concerns::IdempotentStateTransitions

      # Singleton pattern for global event publishing
      def self.instance
        @instance ||= new
      end

      private_class_method :new

      # Initialize the orchestrator
      def initialize
        # Register common workflow events for observability using proper constants
        register_workflow_events
        register_step_events
        register_task_events
      end

      # Register workflow events for observability using existing constants
      def register_workflow_events
        # Task lifecycle events - use existing WorkflowEvents constants
        register_event(Tasker::Constants::WorkflowEvents::TASK_STARTED)
        register_event(Tasker::Constants::WorkflowEvents::TASK_COMPLETED)
        register_event(Tasker::Constants::WorkflowEvents::TASK_FAILED)
        register_event(Tasker::Constants::WorkflowEvents::TASK_REENQUEUE_STARTED)
        register_event(Tasker::Constants::WorkflowEvents::TASK_REENQUEUE_REQUESTED)
        register_event(Tasker::Constants::WorkflowEvents::TASK_REENQUEUE_FAILED)
        register_event(Tasker::Constants::WorkflowEvents::TASK_REENQUEUE_DELAYED)
        register_event(Tasker::Constants::WorkflowEvents::TASK_STATE_UNCLEAR)

        # Step lifecycle events - use existing WorkflowEvents constants
        register_event(Tasker::Constants::WorkflowEvents::STEP_COMPLETED)
        register_event(Tasker::Constants::WorkflowEvents::STEP_FAILED)
        register_event(Tasker::Constants::WorkflowEvents::STEP_EXECUTION_FAILED)

        # Workflow discovery events - use existing WorkflowEvents constants
        register_event(Tasker::Constants::WorkflowEvents::VIABLE_STEPS_DISCOVERED)
        register_event(Tasker::Constants::WorkflowEvents::STEPS_EXECUTION_STARTED)
        register_event(Tasker::Constants::WorkflowEvents::STEPS_EXECUTION_COMPLETED)
        register_event(Tasker::Constants::WorkflowEvents::NO_VIABLE_STEPS)

        # Task finalization events - use existing WorkflowEvents constants
        register_event(Tasker::Constants::WorkflowEvents::TASK_FINALIZATION_STARTED)
        register_event(Tasker::Constants::WorkflowEvents::TASK_FINALIZATION_COMPLETED)
      end

      # Register step events for StepExecutor publishing
      def register_step_events
        # Step execution lifecycle events - use existing StepEvents constants
        register_event(Tasker::Constants::StepEvents::EXECUTION_REQUESTED)
        register_event(Tasker::Constants::StepEvents::COMPLETED)
        register_event(Tasker::Constants::StepEvents::FAILED)
      end

      # Register task events for TaskFinalizer publishing
      def register_task_events
        # Task completion events - use existing TaskEvents constants
        register_event(Tasker::Constants::TaskEvents::COMPLETED)
        register_event(Tasker::Constants::TaskEvents::FAILED)
      end

      # Publish a workflow event for observability
      #
      # @param event_name [String] The event name constant
      # @param payload [Hash] The event payload
      def publish_workflow_event(event_name, payload = {})
        publish(event_name, payload.merge(timestamp: Time.current))
      end
    end
  end
end
