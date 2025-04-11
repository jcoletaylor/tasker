# frozen_string_literal: true

module Tasker
  module Observability
    # OpenTelemetry adapter for telemetry
    class OpenTelemetryAdapter < Adapter
      def initialize
        super
        @tracer = ::OpenTelemetry.tracer_provider.tracer('tasker', Tasker::VERSION)
      end

      def current_span
        @current_span ||= ::OpenTelemetry::Trace.current_span
      end

      def tracer
        @tracer ||= ::OpenTelemetry.tracer_provider.tracer('tasker', Tasker::VERSION)
      end

      # Record an event with the given payload
      # @param event [String] The name of the event
      # @param payload [Hash] The payload data to record
      def record(event, payload = {})
        # Add event to current span if one exists
        return if current_span.nil?

        # Convert payload to attributes
        attributes = convert_payload_to_attributes(payload)
        current_span.add_event(event, attributes: attributes)
      end

      # Start a new trace with the given name and attributes
      # @param name [String] The name of the trace
      # @param attributes [Hash] The attributes to set on the trace
      def start_trace(name, attributes = {})
        otel_attributes = convert_payload_to_attributes(attributes)
        @current_span = tracer.start_root_span(name, attributes: otel_attributes)
      end

      # End the current trace
      def end_trace
        @current_span&.finish
        @current_span = nil
      end

      # Add a span to the current trace
      # @param name [String] The name of the span
      # @param attributes [Hash] The attributes to set on the span
      # @param block [Block] The code to execute within the span
      # @yield Executes the given block within the span
      # @return [Object] The result of the block
      def add_span(name, attributes = {})
        otel_attributes = convert_payload_to_attributes(attributes)

        tracer.in_span(name, attributes: otel_attributes) do |span|
          yield(span) if block_given?
        end
      end

      private

      # Convert hash payload to OTel-compatible attributes
      def convert_payload_to_attributes(payload)
        # Convert all values to strings to make sure they are OTel-compatible
        payload.deep_stringify_keys.deep_transform_values(&:to_s)
      end
    end
  end
end
