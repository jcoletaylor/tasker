# frozen_string_literal: true

require 'dry/events'

module Tasker
  module Events
    # Simple event publisher using dry-events
    #
    # This publisher provides a clean interface for emitting lifecycle events
    # throughout the Tasker system using dry-events best practices.
    class Publisher
      include Dry::Events::Publisher[:tasker]

      # Register state machine transition events
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

      # Register legacy lifecycle events (for backward compatibility)
      register_event(Tasker::Constants::LegacyTaskEvents::HANDLE)
      register_event(Tasker::Constants::LegacyTaskEvents::ENQUEUE)
      register_event(Tasker::Constants::LegacyTaskEvents::FINALIZE)
      register_event(Tasker::Constants::LegacyTaskEvents::ERROR)
      register_event(Tasker::Constants::LegacyTaskEvents::COMPLETE)

      register_event(Tasker::Constants::LegacyStepEvents::FIND_VIABLE)
      register_event(Tasker::Constants::LegacyStepEvents::HANDLE)
      register_event(Tasker::Constants::LegacyStepEvents::COMPLETE)
      register_event(Tasker::Constants::LegacyStepEvents::ERROR)
      register_event(Tasker::Constants::LegacyStepEvents::RETRY)
      register_event(Tasker::Constants::LegacyStepEvents::BACKOFF)
      register_event(Tasker::Constants::LegacyStepEvents::SKIP)
      register_event(Tasker::Constants::LegacyStepEvents::MAX_RETRIES_REACHED)

      # Register workflow orchestration events
      register_event(Tasker::Constants::WorkflowEvents::TASK_STARTED)
      register_event(Tasker::Constants::WorkflowEvents::TASK_COMPLETED)
      register_event(Tasker::Constants::WorkflowEvents::TASK_FAILED)
      register_event(Tasker::Constants::WorkflowEvents::STEP_COMPLETED)
      register_event(Tasker::Constants::WorkflowEvents::STEP_FAILED)
      register_event(Tasker::Constants::WorkflowEvents::ORCHESTRATION_REQUESTED)
      register_event(Tasker::Constants::WorkflowEvents::VIABLE_STEPS_DISCOVERED)
      register_event(Tasker::Constants::WorkflowEvents::NO_VIABLE_STEPS)
      register_event(Tasker::Constants::WorkflowEvents::VIABLE_STEPS_BATCH_READY)
      register_event(Tasker::Constants::WorkflowEvents::STEPS_EXECUTION_STARTED)
      register_event(Tasker::Constants::WorkflowEvents::STEPS_EXECUTION_COMPLETED)
      register_event(Tasker::Constants::WorkflowEvents::STEP_EXECUTION_FAILED)
      register_event(Tasker::Constants::WorkflowEvents::TASK_FINALIZATION_STARTED)
      register_event(Tasker::Constants::WorkflowEvents::TASK_FINALIZATION_COMPLETED)
      register_event(Tasker::Constants::WorkflowEvents::TASK_REENQUEUE_REQUESTED)
      register_event(Tasker::Constants::WorkflowEvents::ITERATION_STARTED)
      register_event(Tasker::Constants::WorkflowEvents::VIABLE_STEPS_BATCH_PROCESSED)
      register_event(Tasker::Constants::WorkflowEvents::ITERATION_COMPLETED)
      register_event(Tasker::Constants::WorkflowEvents::STATE_REFRESHED)
      register_event(Tasker::Constants::WorkflowEvents::SEQUENCE_REGENERATED)

      # Register test events for testing
      register_event('test.event')

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

      # Publish a workflow orchestration event
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
    end
  end
end
