# frozen_string_literal: true

module Tasker
  # Handles lifecycle events for Tasker components using ActiveSupport::Notifications
  #
  # This module provides a clean event firing interface while keeping
  # telemetry logic separate from business logic. Events are used for logging,
  # monitoring, and tracing task and step execution.
  module LifecycleEvents
    # Standard namespace for all Tasker events
    EVENT_NAMESPACE = 'tasker'

    # Event names - used when firing events
    module Events
      # Task-related lifecycle events
      module Task
        # Fired when a task is initialized
        INITIALIZE = 'TaskerTask.Initialize'
        # Fired when a task is started
        START = 'TaskerTask.Start'
        # Fired when a task is handled
        HANDLE = 'TaskerTask.Handle'
        # Fired when a task is enqueued for processing
        ENQUEUE = 'TaskerTask.Enqueue'
        # Fired when a task handling is finalized
        FINALIZE = 'TaskerTask.Finalize'
        # Fired when a task encounters an error
        ERROR = 'TaskerTask.Error'
        # Fired when a task is completed
        COMPLETE = 'TaskerTask.Complete'
      end

      # Step-related lifecycle events
      module Step
        # Fired when viable steps are found
        FIND_VIABLE = 'TaskerStep.FindViable'
        # Fired when a step is handled
        HANDLE = 'TaskerStep.Handle'
        # Fired when a step is completed
        COMPLETE = 'TaskerStep.Complete'
        # Fired when a step encounters an error
        ERROR = 'TaskerStep.Error'
        # Fired when a step is retried
        RETRY = 'TaskerStep.Retry'
        # Fired when a step needs to back off before retrying
        BACKOFF = 'TaskerStep.Backoff'
        # Fired when a step is skipped
        SKIP = 'TaskerStep.Skip'
        # Fired when a step reaches its maximum retry limit
        MAX_RETRIES_REACHED = 'TaskerStep.MaxRetriesReached'
      end
    end

    class << self
      # Fire a lifecycle event with associated context
      #
      # @param event [String] The event name
      # @param context [Hash] The context data associated with the event
      # @yield [void] Optional block to instrument
      # @return [Object, nil] The result of the block if given, otherwise nil
      def fire(event, context = {}, &)
        Rails.logger.debug { "LifecycleEvent fired: #{event} with context: #{context.inspect}" }

        # Create full event name with namespace
        namespaced_event = "#{EVENT_NAMESPACE}.#{event}"

        if block_given?
          # Use ActiveSupport::Notifications to instrument the block
          ActiveSupport::Notifications.instrument(namespaced_event, context, &)
        else
          # Fire event without a block
          ActiveSupport::Notifications.instrument(namespaced_event, context)
        end
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
          exception: [exception.class.name, exception.message],
          exception_object: exception,
          backtrace: exception.backtrace&.join("\n")
        )

        fire(event, error_context)
      end
    end
  end
end
