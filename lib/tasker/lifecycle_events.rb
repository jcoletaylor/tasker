# frozen_string_literal: true

module Tasker
  # Handles lifecycle events for Tasker components
  # This provides a clean event firing interface while keeping
  # telemetry logic separate from business logic
  module LifecycleEvents
    # Event names - used when firing events
    module Events
      module Task
        INITIALIZE = 'task.initialize'
        START = 'task.start'
        HANDLE = 'task.handle'
        ENQUEUE = 'task.enqueue'
        FINALIZE = 'task.finalize'
        ERROR = 'task.error'
        COMPLETE = 'task.complete'
      end

      module Step
        FIND_VIABLE = 'step.find_viable'
        HANDLE = 'step.handle'
        COMPLETE = 'step.complete'
        ERROR = 'step.error'
        RETRY = 'step.retry'
        BACKOFF = 'step.backoff'
        SKIP = 'step.skip'
        MAX_RETRIES_REACHED = 'step.max_retries_reached'
      end
    end

    class << self
      # Fire a lifecycle event with associated context
      # @param event [String] The event name
      # @param context [Hash] The context data associated with the event
      # @param block [Block] Optional block to execute with span tracing
      def fire(event, context = {}, &)
        if block_given?
          fire_with_span(event, context, &)
        else
          notify_observers(event, context)
        end
      end

      # Fire a lifecycle event and wrap the provided block with a span
      # @param event [String] The event name
      # @param context [Hash] The context data associated with the event
      # @param block [Block] The code to execute within the span
      # @yield Executes the given block within a span
      # @return [Object] The result of the block
      def fire_with_span(event, context)
        # Get span name from context or fallback to event name
        span_name = context[:span_name] || event

        # Notify for the start of the event
        notify_observers(event, context)

        # Let observers create spans around the block if needed
        result = nil
        observed_block = proc do
          result = yield
        end

        # Allow observers to trace the execution
        observers.each do |observer|
          if observer.respond_to?(:trace_execution)
            observed_block = observer.trace_execution(span_name, context, &observed_block)
          end
        end

        # Execute the block with all observer spans wrapped around it
        observed_block.call
        result
      end

      # Register an observer to be notified of lifecycle events
      # @param observer [Object] An object that responds to #on_lifecycle_event
      def register_observer(observer)
        unless observer.respond_to?(:on_lifecycle_event)
          raise ArgumentError,
                'Observer must respond to on_lifecycle_event'
        end

        observers << observer unless observers.include?(observer)
      end

      # Unregister an observer
      # @param observer [Object] The observer to remove
      def unregister_observer(observer)
        observers.delete(observer)
      end

      # Reset all observers
      def reset_observers
        @observers = nil
      end

      # Access the current observers
      # @return [Array] The current observers
      def observers
        @observers ||= []
      end

      private

      # Notify all observers of an event
      def notify_observers(event, context)
        observers.each do |observer|
          observer.on_lifecycle_event(event, context)
        rescue StandardError => e
          # Log error but don't let observer failures affect normal operation
          Rails.logger.error("Error in lifecycle observer: #{e.message}") if defined?(Rails)
        end
      end
    end
  end
end
