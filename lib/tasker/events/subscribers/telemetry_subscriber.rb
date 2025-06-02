# frozen_string_literal: true

require_relative '../../constants'
require_relative 'base_subscriber'

module Tasker
  module Events
    module Subscribers
      # TelemetrySubscriber handles telemetry events for observability
      #
      # This subscriber now inherits from BaseSubscriber and uses the declarative
      # subscription pattern with consistent constant usage. It demonstrates how to
      # create specialized subscribers that focus on specific business logic (telemetry)
      # while leveraging the common subscription infrastructure.
      class TelemetrySubscriber < BaseSubscriber
        # Use actual constants for consistent subscription (no string literals)
        subscribe_to Tasker::Constants::TaskEvents::INITIALIZE_REQUESTED,
                     Tasker::Constants::TaskEvents::START_REQUESTED,
                     Tasker::Constants::TaskEvents::COMPLETED,
                     Tasker::Constants::TaskEvents::FAILED,
                     Tasker::Constants::StepEvents::EXECUTION_REQUESTED,
                     Tasker::Constants::StepEvents::COMPLETED,
                     Tasker::Constants::StepEvents::FAILED,
                     Tasker::Constants::StepEvents::RETRY_REQUESTED

        # Handle task initialization events
        def handle_task_initialize_requested(event)
          attributes = extract_core_attributes(event).merge(
            task_name: safe_get(event, :task_name, 'unknown_task')
          )

          record_metric_for_event(Tasker::Constants::TaskEvents::INITIALIZE_REQUESTED, attributes)
        end

        # Handle task start events
        def handle_task_start_requested(event)
          attributes = extract_core_attributes(event).merge(
            task_name: safe_get(event, :task_name, 'unknown_task')
          )

          record_metric_for_event(Tasker::Constants::TaskEvents::START_REQUESTED, attributes)
        end

        # Handle task completion events
        def handle_task_completed(event)
          attributes = extract_core_attributes(event).merge(
            task_name: safe_get(event, :task_name, 'unknown_task'),
            duration: calculate_duration(event),
            total_execution_duration: safe_get(event, :total_execution_duration, 0.0),
            current_execution_duration: safe_get(event, :current_execution_duration, 0.0),
            total_steps: safe_get(event, :total_steps, 0),
            completed_steps: safe_get(event, :completed_steps, 0)
          )

          record_metric_for_event(Tasker::Constants::TaskEvents::COMPLETED, attributes)
        end

        # Handle task failure events
        def handle_task_failed(event)
          attributes = extract_core_attributes(event).merge(
            task_name: safe_get(event, :task_name, 'unknown_task'),
            error: safe_get(event, :error_message, safe_get(event, :error, 'Unknown error')),
            exception_class: safe_get(event, :exception_class, 'StandardError'),
            failed_steps: safe_get(event, :failed_steps, 0)
          )

          record_metric_for_event(Tasker::Constants::TaskEvents::FAILED, attributes)
        end

        # Handle step execution requested events
        def handle_step_execution_requested(event)
          attributes = extract_step_attributes(event).merge(
            attempt_number: safe_get(event, :attempt_number, 1)
          )

          record_metric_for_event(Tasker::Constants::StepEvents::EXECUTION_REQUESTED, attributes)
        end

        # Handle step completion events
        def handle_step_completed(event)
          attributes = extract_step_attributes(event).merge(
            execution_duration: safe_get(event, :execution_duration, 0.0),
            attempt_number: safe_get(event, :attempt_number, 1)
          )

          record_metric_for_event(Tasker::Constants::StepEvents::COMPLETED, attributes)
        end

        # Handle step failure events
        def handle_step_failed(event)
          attributes = extract_step_attributes(event).merge(
            error: safe_get(event, :error_message, safe_get(event, :error, 'Unknown error')),
            attempt_number: safe_get(event, :attempt_number, 1),
            exception_class: safe_get(event, :exception_class, 'StandardError'),
            retry_limit: safe_get(event, :retry_limit, 3)
          )

          record_metric_for_event(Tasker::Constants::StepEvents::FAILED, attributes)
        end

        # Handle step retry events
        def handle_step_retry_requested(event)
          attributes = extract_step_attributes(event).merge(
            attempt_number: safe_get(event, :attempt_number, 1),
            retry_limit: safe_get(event, :retry_limit, 3)
          )

          record_metric_for_event(Tasker::Constants::StepEvents::RETRY_REQUESTED, attributes)
        end

        protected

        # Override BaseSubscriber to add telemetry-specific filtering
        def should_process_event?(event_constant)
          # Only process if telemetry is enabled
          telemetry_enabled? && super
        end

        private

        # Extract step-specific attributes (enhanced from BaseSubscriber)
        def extract_step_attributes(event)
          super.merge(
            step_name: safe_get(event, :step_name, 'unknown_step')
          )
        end

        # Check if telemetry is enabled
        def telemetry_enabled?
          Tasker.configuration.enable_telemetry != false
        end

        # Record a metric for a specific event constant
        #
        # This method derives the metric name from the event constant, ensuring
        # consistency between subscription and metric recording.
        #
        # @param event_constant [String] The event constant (from our Constants)
        # @param attributes [Hash] Event attributes
        def record_metric_for_event(event_constant, attributes = {})
          return unless defined?(Tasker::Instrumentation)

          # Convert event constant to metric name (remove dots, keep structure)
          metric_name = normalize_event_constant_for_metric(event_constant)

          # Filter out nil values to avoid telemetry issues
          clean_attributes = attributes.compact

          send_metric("tasker.#{metric_name}", clean_attributes)
        rescue StandardError => e
          Rails.logger.error("Failed to record telemetry metric for #{event_constant}: #{e.message}")
        end

        # Normalize event constant to metric name format
        #
        # @param event_constant [String] The event constant
        # @return [String] Normalized metric name
        def normalize_event_constant_for_metric(event_constant)
          # Keep the dot-separated format but ensure consistency
          # Examples:
          #   'task.initialize_requested' -> 'task.initialize_requested'
          #   'step.completed' -> 'step.completed'
          event_constant.to_s
        end

        # Actually send the metric to the instrumentation system
        def send_metric(metric_name, attributes)
          Tasker::Instrumentation.record_event(metric_name, attributes)
        end

        # Calculate duration from event timestamps with fallbacks
        def calculate_duration(event)
          started_at = safe_get(event, :started_at)
          completed_at = safe_get(event, :completed_at)

          return nil unless started_at && completed_at

          # Handle different timestamp formats
          start_time = parse_timestamp(started_at)
          end_time = parse_timestamp(completed_at)

          return nil unless start_time && end_time

          (end_time - start_time).round(3)
        rescue StandardError => e
          Rails.logger.warn("Failed to calculate duration for telemetry: #{e.message}")
          nil
        end

        # Parse timestamp in various formats
        #
        # @param timestamp [String, Time, DateTime] The timestamp to parse
        # @return [Time, nil] The parsed time or nil if parsing fails
        def parse_timestamp(timestamp)
          case timestamp
          when Time, DateTime
            timestamp.to_time
          when String
            Time.zone.parse(timestamp) if timestamp.match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
          end
        rescue StandardError
          nil
        end
      end
    end
  end
end
