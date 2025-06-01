# frozen_string_literal: true

require 'benchmark'

module Tasker
  # Legacy LifecycleEvents module - now delegates to unified Events::Publisher
  #
  # This module provides backward compatibility for code that still uses the old
  # LifecycleEvents API. All functionality now delegates to the new Events::Publisher
  # system for consistency.
  #
  # DEPRECATED: Use Events::Publisher.instance directly instead
  module LifecycleEvents
    # Event namespace for ActiveSupport::Notifications compatibility
    EVENT_NAMESPACE = 'tasker'

    class << self
      # Get the unified publisher instance
      #
      # @return [Tasker::Events::Publisher] The publisher instance
      def publisher
        @publisher ||= Tasker::Events::Publisher.instance
      end

      # Legacy method name for backward compatibility
      #
      # @return [Tasker::Events::Publisher] The publisher instance
      def bus
        publisher
      end

      # Fire a lifecycle event using unified Events::Publisher
      #
      # @param event [String] The event name
      # @param context [Hash] The context data associated with the event
      # @yield [void] Optional block to execute within the event context
      # @return [Object, nil] The result of the block if given, otherwise nil
      def fire(event, context = {})
        # Ensure event is registered for test compatibility
        ensure_event_registered(event)

        # Add timing information to context
        started_at = Time.current
        context = context.merge(fired_at: started_at)

        if block_given?
          # For block-based events, measure execution time
          result = nil
          execution_time = Benchmark.realtime do
            result = yield
          end

          context = context.merge(
            execution_duration: execution_time,
            completed_at: Time.current
          )

          # Publish the event with timing through unified publisher
          publisher.publish(event, context)
          result
        else
          # For non-block events, just publish through unified publisher
          publisher.publish(event, context)
          nil
        end
      end

      # Fire an error event with exception details
      #
      # @param event [String] The event name
      # @param exception [Exception] The exception object
      # @param context [Hash] Additional context
      def fire_error(event, exception, context = {})
        error_context = context.merge(
          error: exception.message,
          exception_class: exception.class.name,
          exception_object: exception,
          backtrace: exception.backtrace&.join("\n")
        )

        fire(event, error_context)
      end

      # Subscribe to lifecycle events through unified publisher
      #
      # @param event_name [String] The event name to subscribe to
      # @param callable [Proc, #call] Optional callable object
      # @yield [event] Block to execute when event is fired
      def subscribe(event_name, callable = nil, &block)
        # Ensure event is registered for subscription
        ensure_event_registered(event_name)

        handler = callable || block
        publisher.subscribe(event_name, &handler)
      end

      # Backward compatibility methods (delegate to unified publisher)
      alias fire_with_span fire

      private

      # Ensure an event is registered for test compatibility
      #
      # @param event_name [String] The event name to register
      def ensure_event_registered(event_name)
        # Try to register the event - this handles test events gracefully
        publisher.register_event(event_name)
      rescue StandardError => e
        # If registration fails, log and continue - event may already be registered
        Rails.logger.debug { "Event #{event_name} registration skipped: #{e.message}" }
      end
    end

    # Keep nested constants for backward compatibility
    # These now just reference the same constants used by Events::Publisher
    module Events
      # Task state and lifecycle events
      module Task
        INITIALIZE = Constants::TaskEvents::INITIALIZE_REQUESTED
        START = Constants::TaskEvents::START_REQUESTED
        COMPLETE = Constants::TaskEvents::COMPLETED
        ERROR = Constants::TaskEvents::FAILED
        RETRY = Constants::TaskEvents::RETRY_REQUESTED
        CANCELLED = Constants::TaskEvents::CANCELLED
        RESOLVED_MANUALLY = Constants::TaskEvents::RESOLVED_MANUALLY
      end

      # Step state and lifecycle events
      module Step
        INITIALIZE = Constants::StepEvents::INITIALIZE_REQUESTED
        EXECUTION = Constants::StepEvents::EXECUTION_REQUESTED
        COMPLETE = Constants::StepEvents::COMPLETED
        ERROR = Constants::StepEvents::FAILED
        RETRY = Constants::StepEvents::RETRY_REQUESTED
        CANCELLED = Constants::StepEvents::CANCELLED
        RESOLVED_MANUALLY = Constants::StepEvents::RESOLVED_MANUALLY
      end

      # Reference the same valid events as Events::Publisher
      # This maintains compatibility with existing event validation
      VALID_EVENTS = [
        # Task events
        Constants::TaskEvents::INITIALIZE_REQUESTED,
        Constants::TaskEvents::START_REQUESTED,
        Constants::TaskEvents::COMPLETED,
        Constants::TaskEvents::FAILED,
        Constants::TaskEvents::RETRY_REQUESTED,
        Constants::TaskEvents::CANCELLED,
        Constants::TaskEvents::RESOLVED_MANUALLY,
        Constants::TaskEvents::BEFORE_TRANSITION,

        # Step events
        Constants::StepEvents::INITIALIZE_REQUESTED,
        Constants::StepEvents::EXECUTION_REQUESTED,
        Constants::StepEvents::COMPLETED,
        Constants::StepEvents::FAILED,
        Constants::StepEvents::RETRY_REQUESTED,
        Constants::StepEvents::CANCELLED,
        Constants::StepEvents::RESOLVED_MANUALLY,
        Constants::StepEvents::BEFORE_TRANSITION,

        # Observability events
        Constants::ObservabilityEvents::Task::HANDLE,
        Constants::ObservabilityEvents::Task::ENQUEUE,
        Constants::ObservabilityEvents::Task::FINALIZE,
        Constants::ObservabilityEvents::Step::FIND_VIABLE,
        Constants::ObservabilityEvents::Step::HANDLE,
        Constants::ObservabilityEvents::Step::BACKOFF,
        Constants::ObservabilityEvents::Step::SKIP,
        Constants::ObservabilityEvents::Step::MAX_RETRIES_REACHED,

        # Workflow orchestration events
        Constants::WorkflowEvents::TASK_STARTED,
        Constants::WorkflowEvents::TASK_COMPLETED,
        Constants::WorkflowEvents::TASK_FAILED,
        Constants::WorkflowEvents::TASK_FINALIZATION_STARTED,
        Constants::WorkflowEvents::TASK_FINALIZATION_COMPLETED,
        Constants::WorkflowEvents::TASK_REENQUEUE_STARTED,
        Constants::WorkflowEvents::TASK_REENQUEUE_REQUESTED,
        Constants::WorkflowEvents::TASK_REENQUEUE_FAILED,
        Constants::WorkflowEvents::TASK_REENQUEUE_DELAYED,
        Constants::WorkflowEvents::TASK_STATE_UNCLEAR,
        Constants::WorkflowEvents::STEP_COMPLETED,
        Constants::WorkflowEvents::STEP_FAILED,
        Constants::WorkflowEvents::STEP_EXECUTION_FAILED,
        Constants::WorkflowEvents::VIABLE_STEPS_DISCOVERED,
        Constants::WorkflowEvents::VIABLE_STEPS_BATCH_READY,
        Constants::WorkflowEvents::STEPS_EXECUTION_STARTED,
        Constants::WorkflowEvents::STEPS_EXECUTION_COMPLETED,
        Constants::WorkflowEvents::NO_VIABLE_STEPS,
        Constants::WorkflowEvents::ORCHESTRATION_REQUESTED
      ].freeze
    end
  end
end
