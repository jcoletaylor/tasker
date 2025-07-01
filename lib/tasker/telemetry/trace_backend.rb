# frozen_string_literal: true

require 'concurrent-ruby'
require 'singleton'

module Tasker
  module Telemetry
    # TraceBackend provides thread-safe trace event collection and routing
    #
    # This class implements Tasker's core tracing system with thread-safe operations,
    # automatic EventRouter integration, and support for distributed tracing backends
    # like Jaeger, Zipkin, or OpenTelemetry.
    #
    # The backend follows the same singleton pattern as MetricsBackend for consistency
    # and provides structured trace data collection with span hierarchy support.
    #
    # @example Basic usage
    #   backend = TraceBackend.instance
    #   backend.start_span('task.execution', { task_id: '123' })
    #   backend.finish_span('task.execution', { status: 'success' })
    #
    # @example EventRouter integration
    #   # Automatic trace collection based on event routing
    #   backend.handle_event('task.started', { task_id: '123', context: { user_id: 456 } })
    #
    class TraceBackend
      include Singleton

      # Core trace storage for active spans
      # Using ConcurrentHash for thread-safe operations without locks
      # @return [Concurrent::Hash] Thread-safe trace storage
      attr_reader :traces

      # Backend creation timestamp for monitoring
      # @return [Time] When this backend was initialized
      attr_reader :created_at

      def initialize
        @traces = Concurrent::Hash.new
        @created_at = Time.current
        @instance_id = Socket.gethostname
      end

      # Handle an event from EventRouter and collect appropriate trace data
      #
      # This method is called by EventRouter when an event should be routed to
      # the trace backend. It automatically creates trace spans based on event
      # type and payload.
      #
      # @param event_name [String] The lifecycle event name
      # @param payload [Hash] Event payload with trace data
      # @return [Boolean] True if trace data was collected successfully
      #
      # @example Automatic usage via EventRouter
      #   # EventRouter calls this automatically:
      #   backend.handle_event('task.started', {
      #     task_id: '123',
      #     operation: 'process_payment',
      #     context: { user_id: 456, session_id: 'abc' }
      #   })
      #
      def handle_event(event_name, payload = {})
        return false unless payload.is_a?(Hash)

        trace_data = {
          event_name: event_name,
          timestamp: Time.current.iso8601,
          payload: payload,
          instance_id: @instance_id
        }

        case event_name
        when /\.started$/
          handle_start_event(trace_data)
        when /\.completed$/, /\.failed$/
          handle_finish_event(trace_data)
        when /\.before_/, /\.after_/
          handle_span_event(trace_data)
        else
          handle_generic_event(trace_data)
        end

        true
      rescue StandardError => e
        # Log error but don't raise to prevent breaking the event flow
        Rails.logger&.error("TraceBackend error handling #{event_name}: #{e.message}")
        false
      end

      # Export all collected trace data
      #
      # @return [Hash] All trace data with metadata
      def export
        {
          traces: @traces.each_with_object({}) { |(k, v), h| h[k] = v.dup },
          metadata: {
            backend: 'trace',
            instance_id: @instance_id,
            created_at: @created_at.iso8601,
            exported_at: Time.current.iso8601,
            trace_count: @traces.size
          }
        }
      end

      # Clear all trace data (primarily for testing)
      #
      # @return [void]
      def reset!
        @traces.clear
      end

      # Get trace statistics
      #
      # @return [Hash] Statistics about collected traces
      def stats
        {
          active_traces: @traces.size,
          backend_uptime: Time.current - @created_at,
          instance_id: @instance_id
        }
      end

      private

      def handle_start_event(trace_data)
        trace_key = extract_trace_key(trace_data[:payload])
        @traces[trace_key] = {
          start_time: trace_data[:timestamp],
          event_name: trace_data[:event_name],
          payload: trace_data[:payload],
          spans: []
        }
      end

      def handle_finish_event(trace_data)
        trace_key = extract_trace_key(trace_data[:payload])
        if (trace = @traces[trace_key])
          trace[:end_time] = trace_data[:timestamp]
          trace[:duration] = calculate_duration(trace[:start_time], trace_data[:timestamp])
          trace[:status] = trace_data[:event_name].include?('failed') ? 'error' : 'success'
        end
      end

      def handle_span_event(trace_data)
        trace_key = extract_trace_key(trace_data[:payload])
        if (trace = @traces[trace_key])
          trace[:spans] << {
            timestamp: trace_data[:timestamp],
            event_name: trace_data[:event_name],
            payload: trace_data[:payload]
          }
        end
      end

      def handle_generic_event(trace_data)
        # Store generic events in a special traces collection
        @traces["generic_#{Time.current.to_f}"] = {
          timestamp: trace_data[:timestamp],
          event_name: trace_data[:event_name],
          payload: trace_data[:payload],
          type: 'generic'
        }
      end

      def extract_trace_key(payload)
        # Create a trace key from task_id, workflow_step_id, or other identifiers
        return "task_#{payload[:task_id]}" if payload[:task_id]
        return "step_#{payload[:workflow_step_id]}" if payload[:workflow_step_id]
        return "operation_#{payload[:operation]}" if payload[:operation]
        
        "trace_#{Time.current.to_f}"
      end

      def calculate_duration(start_time, end_time)
        return nil unless start_time && end_time
        
        start_parsed = Time.parse(start_time)
        end_parsed = Time.parse(end_time)
        (end_parsed - start_parsed).round(6)
      rescue StandardError
        nil
      end
    end
  end
end