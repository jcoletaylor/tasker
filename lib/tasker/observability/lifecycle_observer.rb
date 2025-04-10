# frozen_string_literal: true

module Tasker
  module Observability
    # Observer that connects lifecycle events to telemetry system
    class LifecycleObserver
      attr_reader :adapters

      # Initialize the observer with the given adapters
      # And register with the lifecycle events system
      # @param adapters [Array<Tasker::Observability::Adapter>] The adapters to use
      # @return [void]
      def initialize(adapters)
        @adapters = adapters
        validate_adapters!
      end

      # Register the observer with the lifecycle events system
      # @return [void]
      def register!
        Tasker::LifecycleEvents.register_observer(self)
      end

      # Handle a lifecycle event by recording telemetry
      # @param event [String] The event name
      # @param context [Hash] The context data associated with the event
      def on_lifecycle_event(event, context)
        record(event, context)
      end

      # Create a span for tracing execution
      # @param name [String] The span name
      # @param context [Hash] The context data associated with the span
      # @param block [Block] The block to execute within the span
      # @return [Proc] A procedure that executes the block within the span
      def trace_execution(name, context, &block)
        proc do
          add_span(name, context, &block)
        end
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
          Rails.logger.error("Error in telemetry adapter #{adapter.class}: #{e.backtrace.join("\n")}")
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
          Rails.logger.error("Error in telemetry adapter #{adapter.class}: #{e.backtrace.join("\n")}")
        end
      end

      # End the current trace
      def end_trace
        return if adapters.empty?

        adapters.each do |adapter|
          adapter.end_trace if adapter.respond_to?(:end_trace)
        rescue StandardError => e
          # Log error but don't interrupt normal operation
          Rails.logger.error("Error in telemetry adapter #{adapter.class}: #{e.backtrace.join("\n")}")
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
            if defined?(Rails)
              Rails.logger.error("Error in telemetry adapter #{adapter.class}: #{e.backtrace.join("\n")}")
            end
            original_proc.call # Still call the original proc if this adapter fails
          end
        end

        # Execute the final nested proc
        current_proc.call
        result
      end

      # Reset the configured adapters
      def reset_adapters!
        @adapters = nil
      end

      private

      def validate_adapters!
        raise(Tasker::ProceduralError, 'No adapters provided') if @adapters.empty?

        required_methods = %i[record start_trace end_trace add_span]

        @adapters.each do |adapter|
          required_methods.each do |method|
            raise(Tasker::ProceduralError, "Adapter #{adapter.class} does not respond to ##{method}") unless adapter.respond_to?(method)
          end
        end
      end
    end
  end
end
