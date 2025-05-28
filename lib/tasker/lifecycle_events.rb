# frozen_string_literal: true

require_relative 'events/bus'

module Tasker
  # Simplified lifecycle events using dry-events
  #
  # This module provides a clean event firing interface using dry-events
  # publisher/subscriber patterns for decoupled communication.
  module LifecycleEvents
    class << self
      # Get the global event bus
      #
      # @return [Tasker::Events::Bus] The event bus instance
      def bus
        @bus ||= begin
          bus_instance = Tasker::Events::Bus.instance
          bus_instance.setup_default_subscribers
          bus_instance
        end
      end

      # Fire a lifecycle event with associated context
      #
      # @param event [String] The event name
      # @param context [Hash] The context data associated with the event
      # @yield [void] Optional block to instrument
      # @return [Object, nil] The result of the block if given, otherwise nil
      def fire(event, context = {})
        Rails.logger.debug { "LifecycleEvent fired: #{event} with context: #{context.inspect}" }

        if block_given?
          # Execute block and publish event with result
          result = yield
          bus.publish(event, context.merge(result: result))
          result
        else
          # Just publish the event
          bus.publish(event, context)
        end
      rescue StandardError => e
        Rails.logger.error { "Error firing lifecycle event #{event}: #{e.message}" }
        raise
      end

      # Fire an event with span-based tracing
      #
      # This is an alias for backward compatibility that behaves the same
      # as the regular fire method.
      #
      # @param event [String] The event name
      # @param context [Hash] The context data associated with the event
      # @yield [void] Optional block to instrument
      # @return [Object, nil] The result of the block if given, otherwise nil
      def fire_with_span(event, context = {}, &)
        fire(event, context, &)
      end

      # Helper to fire an event with an exception
      #
      # @param event [String] The event name
      # @param exception [Exception] The exception to include
      # @param context [Hash] Additional context data
      # @return [void]
      def fire_error(event, exception, context = {})
        error_context = context.merge(
          error: [exception.class.name, exception.message],
          exception_object: exception,
          backtrace: exception.backtrace&.join("\n")
        )

        fire(event, error_context)
      end

      # Fire a task lifecycle event
      #
      # @param event [String] The event name
      # @param task [Object] The task object
      # @param metadata [Hash] Additional metadata
      def fire_task_event(event, task, metadata = {})
        bus.publish_task_event(event, task, metadata)
      end

      # Fire a step lifecycle event
      #
      # @param event [String] The event name
      # @param step [Object] The step object
      # @param metadata [Hash] Additional metadata
      def fire_step_event(event, step, metadata = {})
        bus.publish_step_event(event, step, metadata)
      end

      # Fire a workflow orchestration event
      #
      # @param event [String] The event name
      # @param context [Hash] The event context
      def fire_workflow_event(event, context = {})
        bus.publish_workflow_event(event, context)
      end

      # Subscribe to events (delegates to bus)
      #
      # @param event_name [String] The event to subscribe to
      # @param callable [Proc, Method] The callback
      def subscribe(event_name, callable = nil, &)
        bus.subscribe(event_name, callable, &)
      end

      # Subscribe an object with event handling methods
      #
      # @param subscriber [Object] Object with event handling methods
      delegate :subscribe_object, to: :bus
    end

    # Event names - kept for backward compatibility
    module Events
      # Task-related lifecycle events
      module Task
        # Fired when a task is initialized
        INITIALIZE = 'task.initialize_requested'
        # Fired when a task is started
        START = 'task.start_requested'
        # Fired when a task is handled
        HANDLE = 'task.handle'
        # Fired when a task is enqueued for processing
        ENQUEUE = 'task.enqueue'
        # Fired when a task handling is finalized
        FINALIZE = 'task.finalize'
        # Fired when a task encounters an error
        ERROR = 'task.error'
        # Fired when a task is completed
        COMPLETE = 'task.complete'
      end

      # Step-related lifecycle events
      module Step
        # Fired when viable steps are found
        FIND_VIABLE = 'step.find_viable'
        # Fired when a step is handled
        HANDLE = 'step.handle'
        # Fired when a step is completed
        COMPLETE = 'step.complete'
        # Fired when a step encounters an error
        ERROR = 'step.error'
        # Fired when a step is retried
        RETRY = 'step.retry'
        # Fired when a step needs to back off before retrying
        BACKOFF = 'step.backoff'
        # Fired when a step is skipped
        SKIP = 'step.skip'
        # Fired when a step reaches its maximum retry limit
        MAX_RETRIES_REACHED = 'step.max_retries_reached'
      end
    end
  end
end
