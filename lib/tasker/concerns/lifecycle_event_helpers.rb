# frozen_string_literal: true

require 'tasker/lifecycle_events'
require_relative 'event_publisher'

module Tasker
  module Concerns
    # LifecycleEventHelpers provides clean methods for firing lifecycle events
    #
    # This concern adds a simple `fire_lifecycle_event` method that eliminates
    # the line noise of the full namespace approach while maintaining all
    # the event firing capabilities.
    module LifecycleEventHelpers
      extend ActiveSupport::Concern
      include EventPublisher

      private

      # Fire a lifecycle event with clean syntax
      #
      # @param event_name [Symbol] The event name (will be resolved to proper constant)
      # @param payload [Hash] The event payload
      def fire_lifecycle_event(event_name, payload = {})
        # Resolve the event name to the proper constant
        event_constant = resolve_event_constant(event_name)

        # Add timestamp if not present
        payload[:timestamp] ||= Time.current

        # Fire the event - this will fail if event isn't registered (which is what we want)
        publish_event(event_constant, payload)
      end

      # Fire a lifecycle error event with exception details
      #
      # @param event_name [Symbol] The event name
      # @param exception [Exception] The exception that occurred
      # @param payload [Hash] Additional payload data
      def fire_lifecycle_error(event_name, exception, payload = {})
        error_payload = payload.merge(
          error_message: exception.message,
          error_class: exception.class.name,
          backtrace: exception.backtrace&.first(10)
        )

        fire_lifecycle_event(event_name, error_payload)
      end

      # Resolve event name symbol to proper event constant
      def resolve_event_constant(event_name)
        case event_name
        # Task events - use existing registered events
        when :task_initialized
          Tasker::LifecycleEvents::Events::Task::INITIALIZE
        when :task_started
          Tasker::LifecycleEvents::Events::Task::START
        when :task_completed
          Tasker::LifecycleEvents::Events::Task::COMPLETE
        when :task_failed
          Tasker::LifecycleEvents::Events::Task::ERROR

        # Step events - use existing registered events
        when :step_execution_requested
          Tasker::LifecycleEvents::Events::Step::EXECUTION
        when :step_completed
          Tasker::LifecycleEvents::Events::Step::COMPLETE
        when :step_failed
          Tasker::LifecycleEvents::Events::Step::ERROR
        when :step_retry_requested
          Tasker::LifecycleEvents::Events::Step::RETRY

        # Workflow events - use existing WorkflowEvents constants
        when :viable_steps_discovery_started
          # No existing constant - use a related one or raise error
          raise ArgumentError, 'Event :viable_steps_discovery_started not registered. Use existing workflow events.'
        when :viable_steps_discovered
          Tasker::Constants::WorkflowEvents::VIABLE_STEPS_DISCOVERED
        when :viable_steps_processing_started
          Tasker::Constants::WorkflowEvents::STEPS_EXECUTION_STARTED
        when :viable_steps_processing_completed
          Tasker::Constants::WorkflowEvents::STEPS_EXECUTION_COMPLETED
        when :no_viable_steps
          Tasker::Constants::WorkflowEvents::NO_VIABLE_STEPS
        when :task_finalization_started
          Tasker::Constants::WorkflowEvents::TASK_FINALIZATION_STARTED
        when :task_finalization_completed
          Tasker::Constants::WorkflowEvents::TASK_FINALIZATION_COMPLETED
        when :task_blocked_by_errors
          # No existing constant - raise error to indicate missing registration
          raise ArgumentError, 'Event :task_blocked_by_errors not registered. Add to WorkflowEvents constants.'
        when :task_requeued
          Tasker::Constants::WorkflowEvents::TASK_REENQUEUE_REQUESTED

        else
          # Unknown event - raise error to indicate missing registration
          raise ArgumentError, "Unknown event: #{event_name}. Register the event constant first."
        end
      end
    end
  end
end
