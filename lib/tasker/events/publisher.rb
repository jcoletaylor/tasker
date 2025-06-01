# frozen_string_literal: true

require 'dry/events'
require_relative '../concerns/idempotent_state_transitions'

module Tasker
  module Events
    # Unified event publisher for the Tasker system
    #
    # This publisher provides a comprehensive interface for emitting lifecycle events,
    # workflow orchestration events, and observability events throughout the Tasker
    # system using dry-events best practices. It serves as the single event publisher
    # for all components including orchestration.
    class Publisher
      include Dry::Events::Publisher[:tasker]
      include Tasker::Concerns::IdempotentStateTransitions

      # Singleton pattern for global event publishing (merged from Orchestrator)
      def self.instance
        @instance ||= new
      end

      private_class_method :new

      def initialize
        # Register all events during initialization
        register_all_events
      end

      private

      # Register all event types
      def register_all_events
        register_state_machine_events
        register_lifecycle_events
        register_observability_events
        register_workflow_events
        register_test_events
      end

      # Register state machine transition events
      def register_state_machine_events
        register_event(Tasker::Constants::TaskEvents::INITIALIZE_REQUESTED)
        register_event(Tasker::Constants::TaskEvents::START_REQUESTED)
        register_event(Tasker::Constants::TaskEvents::BEFORE_TRANSITION)
        register_event(Tasker::Constants::TaskEvents::COMPLETED)
        register_event(Tasker::Constants::TaskEvents::FAILED)
        register_event(Tasker::Constants::TaskEvents::RETRY_REQUESTED)
        register_event(Tasker::Constants::TaskEvents::RESOLVED_MANUALLY)
        register_event(Tasker::Constants::TaskEvents::CANCELLED)

        register_event(Tasker::Constants::StepEvents::INITIALIZE_REQUESTED)
        register_event(Tasker::Constants::StepEvents::EXECUTION_REQUESTED)
        register_event(Tasker::Constants::StepEvents::BEFORE_TRANSITION)
        register_event(Tasker::Constants::StepEvents::COMPLETED)
        register_event(Tasker::Constants::StepEvents::FAILED)
        register_event(Tasker::Constants::StepEvents::RETRY_REQUESTED)
        register_event(Tasker::Constants::StepEvents::RESOLVED_MANUALLY)
        register_event(Tasker::Constants::StepEvents::CANCELLED)
      end

      # Register lifecycle events (these align with LifecycleEvents)
      def register_lifecycle_events
        # Register if constants exist
        if defined?(Tasker::Constants::LifecycleEvents)
          register_event(Tasker::Constants::LifecycleEvents::TASK_INITIALIZE_REQUESTED)
          register_event(Tasker::Constants::LifecycleEvents::TASK_START_REQUESTED)
        end
      end

      # Register observability/process tracking events
      def register_observability_events
        register_event(Tasker::Constants::ObservabilityEvents::Task::HANDLE)
        register_event(Tasker::Constants::ObservabilityEvents::Task::ENQUEUE)
        register_event(Tasker::Constants::ObservabilityEvents::Task::FINALIZE)
        register_event(Tasker::Constants::ObservabilityEvents::Step::FIND_VIABLE)
        register_event(Tasker::Constants::ObservabilityEvents::Step::HANDLE)
        register_event(Tasker::Constants::ObservabilityEvents::Step::BACKOFF)
        register_event(Tasker::Constants::ObservabilityEvents::Step::SKIP)
        register_event(Tasker::Constants::ObservabilityEvents::Step::MAX_RETRIES_REACHED)
      end

      # Register workflow orchestration events (comprehensive set from both Publisher and Orchestrator)
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
        # Register test events if constants exist
        if defined?(Tasker::Constants::TestEvents)
          register_event(Tasker::Constants::TestEvents::BASIC_EVENT)
          register_event(Tasker::Constants::TestEvents::SLOW_EVENT)
          register_event(Tasker::Constants::TestEvents::TEST_EVENT)
        end

        # Also register common test event patterns
        register_event('Test.Event')  # Common test event name
      end

      public

      # Publish a task lifecycle event
      #
      # @param event_name [String] The event name
      # @param task [Object] The task object
      # @param metadata [Hash] Additional event data
      def publish_task_event(event_name, task, metadata = {})
        event_data = {
          task_id: task.respond_to?(:task_id) ? task.task_id : task.id,
          task_name: task.respond_to?(:name) ? task.name : nil,
          status: task.respond_to?(:status) ? task.status : nil,
          timestamp: Time.current
        }.merge(metadata).compact

        publish(event_name, event_data)
      end

      # Publish a step lifecycle event
      #
      # @param event_name [String] The event name
      # @param step [Object] The step object
      # @param metadata [Hash] Additional event data
      def publish_step_event(event_name, step, metadata = {})
        event_data = {
          step_id: step.respond_to?(:workflow_step_id) ? step.workflow_step_id : step.id,
          step_name: step.respond_to?(:name) ? step.name : nil,
          task_id: step.respond_to?(:task_id) ? step.task_id : nil,
          status: step.respond_to?(:status) ? step.status : nil,
          timestamp: Time.current
        }.merge(metadata).compact

        publish(event_name, event_data)
      end

      # Publish a workflow orchestration event (merged from Orchestrator)
      #
      # @param event_name [String] The event name
      # @param context [Hash] The event context
      def publish_workflow_event(event_name, context = {})
        event_data = {
          timestamp: Time.current
        }.merge(context).compact

        publish(event_name, event_data)
      end

      # Publish a generic event with minimal ceremony
      #
      # @param event_name [String] The event name
      # @param payload [Hash] The event payload
      def publish_event(event_name, payload = {})
        event_data = {
          timestamp: Time.current
        }.merge(payload).compact

        publish(event_name, event_data)
      end

      # Convenience methods for common workflow events (merged from Orchestrator)
      # These provide a more intuitive API for the orchestration components

      def publish_task_started(payload = {})
        publish_workflow_event(Tasker::Constants::WorkflowEvents::TASK_STARTED, payload)
      end

      def publish_task_completed(payload = {})
        publish_workflow_event(Tasker::Constants::WorkflowEvents::TASK_COMPLETED, payload)
      end

      def publish_step_completed(payload = {})
        publish_workflow_event(Tasker::Constants::WorkflowEvents::STEP_COMPLETED, payload)
      end

      def publish_viable_steps_discovered(payload = {})
        publish_workflow_event(Tasker::Constants::WorkflowEvents::VIABLE_STEPS_DISCOVERED, payload)
      end

      def publish_no_viable_steps(payload = {})
        publish_workflow_event(Tasker::Constants::WorkflowEvents::NO_VIABLE_STEPS, payload)
      end
    end
  end
end
