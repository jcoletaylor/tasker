# frozen_string_literal: true

module Tasker
  module Telemetry
    # Lifecycle events for tasks and steps - kept for compatibility
    # These are now defined in Tasker::LifecycleEvents::Events
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
        SKIP = 'step.skip'
        MAX_RETRIES_REACHED = 'step.max_retries_reached'
      end
    end

    # Telemetry helper methods
    class << self
      # Initialize the telemetry system
      # This sets up observers and connects them to the lifecycle events
      def initialize
        return unless Tasker.configuration.enable_telemetry

        require 'tasker/telemetry/observer'
        Observer.instance # Create and register the observer
      end

      # Record an event with the given payload
      # @param event [String] The event name
      # @param payload [Hash] The payload data to record
      def record(event, payload = {})
        return if adapters.empty?

        adapters.each do |adapter|
          adapter.record(event, payload)
        rescue StandardError => e
          # Log error but don't interrupt normal operation
          Rails.logger.error("Error in telemetry adapter #{adapter.class}: #{e.backtrace.join("\n")}") if defined?(Rails)
        end
      end

      # Start a trace with the given name and attributes
      # @param name [String] The name of the trace
      # @param attributes [Hash] The attributes to set on the trace
      def start_trace(name, attributes = {})
        return if adapters.empty?

        adapters.each do |adapter|
          adapter.start_trace(name, attributes) if adapter.respond_to?(:start_trace)
        rescue StandardError => e
          # Log error but don't interrupt normal operation
          Rails.logger.error("Error in telemetry adapter #{adapter.class}: #{e.backtrace.join("\n")}") if defined?(Rails)
        end
      end

      # End the current trace
      def end_trace
        return if adapters.empty?

        adapters.each do |adapter|
          adapter.end_trace if adapter.respond_to?(:end_trace)
        rescue StandardError => e
          # Log error but don't interrupt normal operation
          Rails.logger.error("Error in telemetry adapter #{adapter.class}: #{e.backtrace.join("\n")}") if defined?(Rails)
        end
      end

      # Add a span to the current trace
      # @param name [String] The name of the span
      # @param attributes [Hash] The attributes to set on the span
      # @param block [Block] The code to execute within the span
      # @yield Executes the given block within the span
      # @return [Object] The result of the block
      def add_span(name, attributes = {})
        return yield if adapters.empty?

        # We need to chain the spans for each adapter
        result = nil
        current_proc = proc { result = yield }

        # Wrap the block with each adapter's span in reverse order
        adapters.reverse_each do |adapter|
          next unless adapter.respond_to?(:add_span)

          # Capture the current proc in the closure
          original_proc = current_proc

          # Create a new proc that will call the adapter's add_span with the original proc
          current_proc = proc do
            adapter.add_span(name, attributes) { original_proc.call }
          rescue StandardError => e
            # Log error but don't interrupt normal operation
            Rails.logger.error("Error in telemetry adapter #{adapter.class}: #{e.backtrace.join("\n")}") if defined?(Rails)
            original_proc.call # Still call the original proc if this adapter fails
          end
        end

        # Execute the final nested proc
        current_proc.call
        result
      end

      # Get the configured adapters
      # @return [Array] The configured telemetry adapters
      def adapters
        @adapters ||= Tasker.configuration.telemetry_adapter_instances
      end

      # Reset the configured adapters
      def reset_adapters!
        @adapters = nil
      end
    end
  end
end
