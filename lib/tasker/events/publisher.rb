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

      # Register common event types
      register_event('task.initialize_requested')
      register_event('task.start_requested')
      register_event('task.handle')
      register_event('task.complete')
      register_event('task.error')
      register_event('task.enqueue')
      register_event('task.finalize')
      register_event('task.before_transition')
      register_event('task.completed')
      register_event('task.failed')
      register_event('task.retry_requested')
      register_event('task.resolved_manually')
      register_event('task.cancelled')

      register_event('step.find_viable')
      register_event('step.handle')
      register_event('step.complete')
      register_event('step.error')
      register_event('step.retry')
      register_event('step.backoff')
      register_event('step.skip')
      register_event('step.max_retries_reached')
      register_event('step.before_transition')
      register_event('step.execution_requested')
      register_event('step.completed')
      register_event('step.failed')
      register_event('step.retry_requested')
      register_event('step.resolved_manually')
      register_event('step.cancelled')

      register_event('workflow.iteration_started')
      register_event('workflow.viable_steps_batch_processed')
      register_event('workflow.iteration_completed')
      register_event('workflow.state_refreshed')
      register_event('workflow.sequence_regenerated')

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
