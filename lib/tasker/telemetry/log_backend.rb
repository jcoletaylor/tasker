# frozen_string_literal: true

require 'concurrent-ruby'
require 'singleton'

module Tasker
  module Telemetry
    # LogBackend provides thread-safe structured logging for events
    #
    # This class implements Tasker's core logging system with thread-safe operations,
    # automatic EventRouter integration, and structured log data collection.
    # It complements Rails logging with structured event data suitable for
    # log aggregation systems like ELK, Splunk, or Fluentd.
    #
    # The backend follows the same singleton pattern as MetricsBackend for consistency
    # and provides structured log data with correlation IDs and contextual information.
    #
    # @example Basic usage
    #   backend = LogBackend.instance
    #   backend.log_event('task.started', { task_id: '123', level: 'info' })
    #
    # @example EventRouter integration
    #   # Automatic log collection based on event routing
    #   backend.handle_event('task.failed', { task_id: '123', error: 'timeout', level: 'error' })
    #
    class LogBackend
      include Singleton

      # Core log storage for structured events
      # Using ConcurrentHash for thread-safe operations without locks
      # @return [Concurrent::Hash] Thread-safe log storage
      attr_reader :logs

      # Backend creation timestamp for monitoring
      # @return [Time] When this backend was initialized
      attr_reader :created_at

      # Log levels in order of severity
      LOG_LEVELS = %w[debug info warn error fatal].freeze

      def initialize
        @logs = Concurrent::Hash.new { |h, k| h[k] = Concurrent::Array.new }
        @created_at = Time.current
        @instance_id = Socket.gethostname
      end

      # Handle an event from EventRouter and collect appropriate log data
      #
      # This method is called by EventRouter when an event should be routed to
      # the log backend. It automatically creates structured log entries based on
      # event type and payload.
      #
      # @param event_name [String] The lifecycle event name
      # @param payload [Hash] Event payload with log data
      # @return [Boolean] True if log data was collected successfully
      #
      # @example Automatic usage via EventRouter
      #   # EventRouter calls this automatically:
      #   backend.handle_event('task.failed', {
      #     task_id: '123',
      #     error: 'Payment gateway timeout',
      #     context: { user_id: 456, amount: 100.0 }
      #   })
      #
      def handle_event(event_name, payload = {})
        return false unless payload.is_a?(Hash)

        log_entry = {
          timestamp: Time.current.iso8601,
          event_name: event_name,
          level: determine_log_level(event_name),
          message: build_log_message(event_name, payload),
          payload: payload,
          instance_id: @instance_id,
          correlation_id: extract_correlation_id(payload)
        }

        # Store log entry by level for organized retrieval
        level = log_entry[:level]
        @logs[level] << log_entry

        # Also store in chronological order
        @logs[:all] << log_entry

        true
      rescue StandardError => e
        # Log error but don't raise to prevent breaking the event flow
        Rails.logger&.error("LogBackend error handling #{event_name}: #{e.message}")
        false
      end

      # Export all collected log data
      #
      # @param level [String, nil] Specific log level to export, or nil for all
      # @return [Hash] Log data with metadata
      def export(level: nil)
        logs_to_export = if level && LOG_LEVELS.include?(level.to_s)
                           { level.to_s => @logs[level.to_s].to_a }
                         else
                           @logs.each_with_object({}) { |(k, v), h| h[k.to_s] = v.to_a }
                         end

        {
          logs: logs_to_export,
          metadata: {
            backend: 'log',
            instance_id: @instance_id,
            created_at: @created_at.iso8601,
            exported_at: Time.current.iso8601,
            total_entries: @logs[:all]&.size || 0,
            level_counts: LOG_LEVELS.to_h { |l| [l, @logs[l]&.size || 0] }
          }
        }
      end

      # Clear all log data (primarily for testing)
      #
      # @return [void]
      def reset!
        @logs.clear
      end

      # Get log statistics
      #
      # @return [Hash] Statistics about collected logs
      def stats
        {
          total_entries: @logs[:all]&.size || 0,
          level_counts: LOG_LEVELS.to_h { |level| [level, @logs[level]&.size || 0] },
          backend_uptime: Time.current - @created_at,
          instance_id: @instance_id
        }
      end

      # Get recent log entries
      #
      # @param limit [Integer] Number of recent entries to return
      # @param level [String, nil] Specific log level to filter by
      # @return [Array<Hash>] Recent log entries
      def recent_entries(limit: 100, level: nil)
        entries = if level && LOG_LEVELS.include?(level.to_s)
                    @logs[level.to_s].to_a
                  else
                    @logs[:all]&.to_a || []
                  end

        entries.last(limit)
      end

      private

      def determine_log_level(event_name)
        case event_name
        when /\.failed$/, /\.error$/
          'error'
        when /\.warn$/, /\.warning$/
          'warn'
        when /\.started$/, /\.completed$/
          'info'
        when /\.debug$/, /\.trace$/
          'debug'
        else
          'info'
        end
      end

      def build_log_message(event_name, payload)
        # Create a human-readable message from the event and payload
        entity_type = extract_entity_type(event_name)
        action = extract_action(event_name)
        
        base_message = "#{entity_type.capitalize} #{action}"
        
        # Add key details from payload
        details = []
        details << "ID: #{payload[:task_id]}" if payload[:task_id]
        details << "Step: #{payload[:workflow_step_id]}" if payload[:workflow_step_id]
        details << "Error: #{payload[:error]}" if payload[:error]
        details << "Duration: #{payload[:duration]}s" if payload[:duration]
        
        details.empty? ? base_message : "#{base_message} (#{details.join(', ')})"
      end

      def extract_entity_type(event_name)
        case event_name
        when /^task\./
          'task'
        when /^step\./
          'step'
        when /^workflow\./
          'workflow'
        else
          'system'
        end
      end

      def extract_action(event_name)
        case event_name
        when /\.started$/
          'started'
        when /\.completed$/
          'completed'
        when /\.failed$/
          'failed'
        when /\.before_/
          'preparing'
        when /\.after_/
          'finished'
        else
          'event'
        end
      end

      def extract_correlation_id(payload)
        # Extract correlation ID for log tracing
        payload[:correlation_id] ||
          payload[:request_id] ||
          payload[:task_id] ||
          payload[:workflow_step_id] ||
          SecureRandom.uuid
      end
    end
  end
end