# frozen_string_literal: true

module Tasker
  module Observability
    # Base adapter interface for telemetry
    class Adapter
      def initialize
        # Do nothing by default
      end

      # Record an event with the given payload
      # @param event [String] The name of the event
      # @param payload [Hash] The payload data to record
      def record(event, payload = {})
        raise NotImplementedError, 'Subclasses must implement #record'
      end

      # Optional trace/span methods for distributed tracing adapters

      # Start a new trace with the given name and attributes
      # @param name [String] The name of the trace
      # @param attributes [Hash] The attributes to set on the trace
      def start_trace(name, attributes = {})
        # Optional - override in subclasses that support tracing
      end

      # End the current trace
      def end_trace
        # Optional - override in subclasses that support tracing
      end

      # Add a span to the current trace
      # @param name [String] The name of the span
      # @param attributes [Hash] The attributes to set on the span
      # @param block [Block] The code to execute within the span
      # @yield Executes the given block within the span
      # @return [Object] The result of the block
      def add_span(_name, _attributes = {})
        # By default, just run the block without tracing
        yield if block_given?
      end
    end
  end
end
