# frozen_string_literal: true

module Tasker
  module Telemetry
    # OpenTelemetry adapter for telemetry
    class OpenTelemetryAdapter < Adapter
      def initialize
        super
        require_opentelemetry_gems
      end

      # Record an event with the given payload
      # @param event [String] The name of the event
      # @param payload [Hash] The payload data to record
      def record(event, payload = {})
        # Add event to current span if one exists
        current_span = ::OpenTelemetry::Trace.current_span
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
        @tracer ||= ::OpenTelemetry.tracer_provider.tracer('tasker', Tasker::VERSION)
        @current_span = @tracer.start_root_span(name, attributes: otel_attributes)
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
        @tracer ||= ::OpenTelemetry.tracer_provider.tracer('tasker', Tasker::VERSION)

        @tracer.in_span(name, attributes: otel_attributes) do |span|
          yield(span) if block_given?
        end
      end

      private

      def require_opentelemetry_gems
        require 'opentelemetry/sdk'
        require 'opentelemetry/instrumentation/all'
      rescue LoadError => e
        Rails.logger.error "OpenTelemetry gems not found: #{e.message}"
        Rails.logger.error "Please add 'opentelemetry-sdk' and 'opentelemetry-instrumentation-all' to your Gemfile"
        raise
      end

      # Convert hash payload to OTel-compatible attributes
      def convert_payload_to_attributes(payload)
        # Convert all values to strings to make sure they are OTel-compatible
        payload.transform_values(&:to_s)
      end
    end
  end
end
