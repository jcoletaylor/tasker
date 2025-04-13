# frozen_string_literal: true

module Tasker
  # Handles lifecycle events for Tasker components using ActiveSupport::Notifications
  # This provides a clean event firing interface while keeping
  # telemetry logic separate from business logic
  module LifecycleEvents
    # Standard namespace for all Tasker events
    EVENT_NAMESPACE = 'tasker'

    # Event names - used when firing events
    module Events
      module Task
        INITIALIZE = 'TaskerTask.Initialize'
        START = 'TaskerTask.Start'
        HANDLE = 'TaskerTask.Handle'
        ENQUEUE = 'TaskerTask.Enqueue'
        FINALIZE = 'TaskerTask.Finalize'
        ERROR = 'TaskerTask.Error'
        COMPLETE = 'TaskerTask.Complete'
      end

      module Step
        FIND_VIABLE = 'TaskerStep.FindViable'
        HANDLE = 'TaskerStep.Handle'
        COMPLETE = 'TaskerStep.Complete'
        ERROR = 'TaskerStep.Error'
        RETRY = 'TaskerStep.Retry'
        BACKOFF = 'TaskerStep.Backoff'
        SKIP = 'TaskerStep.Skip'
        MAX_RETRIES_REACHED = 'TaskerStep.MaxRetriesReached'
      end
    end

    class << self
      # Fire a lifecycle event with associated context
      # @param event [String] The event name
      # @param context [Hash] The context data associated with the event
      # @param block [Block] Optional block to execute with span tracing
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

      # Alias for backwards compatibility
      # @param event [String] The event name
      # @param context [Hash] The context data associated with the event
      # @param block [Block] Block to execute with span tracing
      def fire_with_span(event, context = {}, &)
        fire(event, context, &)
      end

      # Helper to fire an event with an exception
      # @param event [String] The event name
      # @param exception [Exception] The exception to include
      # @param context [Hash] Additional context data
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
