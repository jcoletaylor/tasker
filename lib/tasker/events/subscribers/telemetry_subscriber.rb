# frozen_string_literal: true

require_relative '../../constants'
require_relative 'base_subscriber'

module Tasker
  module Events
    module Subscribers
      # TelemetrySubscriber handles telemetry events for observability
      #
      # This subscriber creates OpenTelemetry spans with proper hierarchical context
      # for distributed tracing in systems like Jaeger. It follows OpenTelemetry
      # best practices by creating detailed spans for debugging while allowing
      # metrics to be derived from span data.
      #
      # Architecture Decision:
      # - SPANS: Individual trace records for detailed debugging (this class)
      # - METRICS: Aggregated data for dashboards/alerts (derived from spans or separate collectors)
      class TelemetrySubscriber < BaseSubscriber
        attr_accessor :tracer

        # Use actual constants for consistent subscription (no string literals)
        subscribe_to Tasker::Constants::TaskEvents::INITIALIZE_REQUESTED,
                     Tasker::Constants::TaskEvents::START_REQUESTED,
                     Tasker::Constants::TaskEvents::COMPLETED,
                     Tasker::Constants::TaskEvents::FAILED,
                     Tasker::Constants::StepEvents::EXECUTION_REQUESTED,
                     Tasker::Constants::StepEvents::COMPLETED,
                     Tasker::Constants::StepEvents::FAILED,
                     Tasker::Constants::StepEvents::RETRY_REQUESTED

        def initialize
          super
          @tracer = create_tracer
        end

        # Handle task initialization events
        def handle_task_initialize_requested(event)
          return unless should_process_event?(Tasker::Constants::TaskEvents::INITIALIZE_REQUESTED)

          attributes = extract_core_attributes(event).merge(
            task_name: safe_get(event, :task_name, 'unknown_task')
          )

          # Only create basic span for initialization - task.start_requested will create the main span
          create_simple_span(event, 'tasker.task.initialize', attributes)
        end

        # Handle task start events
        def handle_task_start_requested(event)
          return unless should_process_event?(Tasker::Constants::TaskEvents::START_REQUESTED)

          attributes = extract_core_attributes(event).merge(
            task_name: safe_get(event, :task_name, 'unknown_task')
          )

          # Create root span for task and store it for child spans
          create_task_span(event, 'tasker.task.execution', attributes)
        end

        # Handle task completion events
        def handle_task_completed(event)
          return unless should_process_event?(Tasker::Constants::TaskEvents::COMPLETED)

          attributes = extract_core_attributes(event).merge(
            task_name: safe_get(event, :task_name, 'unknown_task'),
            duration: calculate_duration(event),
            total_execution_duration: safe_get(event, :total_execution_duration, 0.0),
            current_execution_duration: safe_get(event, :current_execution_duration, 0.0),
            total_steps: safe_get(event, :total_steps, 0),
            completed_steps: safe_get(event, :completed_steps, 0)
          )

          # Finish the task span with success status
          finish_task_span(event, :ok, attributes)
        end

        # Handle task failure events
        def handle_task_failed(event)
          return unless should_process_event?(Tasker::Constants::TaskEvents::FAILED)

          attributes = extract_core_attributes(event).merge(
            task_name: safe_get(event, :task_name, 'unknown_task'),
            error: safe_get(event, :error_message, safe_get(event, :error, 'Unknown error')),
            exception_class: safe_get(event, :exception_class, 'StandardError'),
            failed_steps: safe_get(event, :failed_steps, 0)
          )

          # Finish the task span with error status
          finish_task_span(event, :error, attributes)
        end

        # Handle step execution requested events
        def handle_step_execution_requested(event)
          return unless should_process_event?(Tasker::Constants::StepEvents::EXECUTION_REQUESTED)

          attributes = extract_step_attributes(event).merge(
            attempt_number: safe_get(event, :attempt_number, 1)
          )

          # Create a simple span for step queuing
          create_simple_span(event, 'tasker.step.queued', attributes)
        end

        # Handle step completion events
        def handle_step_completed(event)
          return unless should_process_event?(Tasker::Constants::StepEvents::COMPLETED)

          attributes = extract_step_attributes(event).merge(
            execution_duration: safe_get(event, :execution_duration, 0.0),
            attempt_number: safe_get(event, :attempt_number, 1)
          )

          # Create step span as child of task span
          create_step_span(event, 'tasker.step.execution', attributes, :ok)
        end

        # Handle step failure events
        def handle_step_failed(event)
          return unless should_process_event?(Tasker::Constants::StepEvents::FAILED)

          attributes = extract_step_attributes(event).merge(
            error: safe_get(event, :error_message, safe_get(event, :error, 'Unknown error')),
            attempt_number: safe_get(event, :attempt_number, 1),
            exception_class: safe_get(event, :exception_class, 'StandardError'),
            retry_limit: safe_get(event, :retry_limit, 3)
          )

          # Create step span as child of task span with error status
          create_step_span(event, 'tasker.step.execution', attributes, :error)
        end

        # Handle step retry events
        def handle_step_retry_requested(event)
          return unless should_process_event?(Tasker::Constants::StepEvents::RETRY_REQUESTED)

          attributes = extract_step_attributes(event).merge(
            attempt_number: safe_get(event, :attempt_number, 1),
            retry_limit: safe_get(event, :retry_limit, 3)
          )

          # Create a simple span for retry events
          create_simple_span(event, 'tasker.step.retry', attributes)
        end

        # Override BaseSubscriber to add telemetry-specific filtering
        def should_process_event?(event_constant)
          # Get configuration once for efficiency
          config = Tasker::Configuration.configuration

          # Only process if telemetry is enabled
          return false unless config.telemetry.enabled

          super
        end

        # Extract step-specific attributes (enhanced from BaseSubscriber)
        def extract_step_attributes(event)
          super.merge(
            step_name: safe_get(event, :step_name, 'unknown_step')
          )
        end

        # Check if telemetry is enabled
        def telemetry_enabled?
          Tasker::Configuration.configuration.telemetry.enabled != false
        end

        # Create a simple span for events that don't need complex hierarchy
        #
        # @param event [Hash] The event data
        # @param span_name [String] The name for the span
        # @param attributes [Hash] Span attributes
        def create_simple_span(event, span_name, attributes)
          return unless opentelemetry_available?

          otel_attributes = convert_attributes_for_otel(attributes)

          tracer.in_span(span_name, attributes: otel_attributes) do |span|
            # Add event annotation
            span.add_event(event_to_annotation_name(event), attributes: otel_attributes)
          end
        rescue StandardError => e
          Rails.logger.warn("Failed to create simple span: #{e.message}")
        end

        # Create a root span for a task and store it for child spans
        #
        # @param event [Hash] The event data
        # @param span_name [String] The name for the span
        # @param attributes [Hash] Span attributes
        def create_task_span(event, span_name, attributes)
          return unless opentelemetry_available?

          task_id = safe_get(event, :task_id)
          return unless task_id

          otel_attributes = convert_attributes_for_otel(attributes)

          span = tracer.start_root_span(span_name, attributes: otel_attributes)
          store_task_span(task_id, span)

          # Add an event to mark the task start
          span.add_event('task.started', attributes: otel_attributes)
        rescue StandardError => e
          Rails.logger.warn("Failed to create task span: #{e.message}")
        end

        # Finish a task span with the appropriate status
        #
        # @param event [Hash] The event data
        # @param status [Symbol] The span status (:ok or :error)
        # @param attributes [Hash] Final span attributes
        def finish_task_span(event, status, attributes)
          return unless opentelemetry_available?

          task_id = safe_get(event, :task_id)
          return unless task_id

          span = get_task_span(task_id)
          return unless span

          otel_attributes = convert_attributes_for_otel(attributes)

          # Add completion event
          event_name = status == :error ? 'task.failed' : 'task.completed'
          span.add_event(event_name, attributes: otel_attributes)

          # Set span status
          set_span_status(span, status, attributes)

          # Finish the span
          span.finish
          remove_task_span(task_id)
        rescue StandardError => e
          Rails.logger.warn("Failed to finish task span: #{e.message}")
        end

        # Create a step span as a child of the task span
        #
        # @param event [Hash] The event data
        # @param span_name [String] The name for the span
        # @param attributes [Hash] Span attributes
        # @param status [Symbol] The span status (:ok or :error)
        def create_step_span(event, span_name, attributes, status)
          return unless opentelemetry_available?

          task_id = safe_get(event, :task_id)
          step_id = safe_get(event, :step_id)
          return unless task_id && step_id

          task_span = get_task_span(task_id)
          return unless task_span

          otel_attributes = convert_attributes_for_otel(attributes)

          # Create child span context
          span_context = ::OpenTelemetry::Trace.context_with_span(task_span)

          ::OpenTelemetry::Context.with_current(span_context) do
            tracer.in_span(span_name, attributes: otel_attributes) do |step_span|
              # Add step event
              event_name = status == :error ? 'step.failed' : 'step.completed'
              step_span.add_event(event_name, attributes: otel_attributes)

              # Set span status
              set_span_status(step_span, status, attributes)
            end
          end
        rescue StandardError => e
          Rails.logger.warn("Failed to create step span: #{e.message}")
        end

        # Event type to annotation name mapping
        EVENT_ANNOTATION_MAP = {
          'initialize_requested' => 'task.initialize',
          'execution_requested' => 'step.queued',
          'retry_requested' => 'step.retry'
        }.freeze

        # Convert event to annotation name
        def event_to_annotation_name(event)
          # Simple mapping from event to annotation
          event_type = safe_get(event, :event_type)
          EVENT_ANNOTATION_MAP.fetch(event_type, 'event.processed')
        end

        # Check if OpenTelemetry is available and configured
        #
        # @return [Boolean] True if OpenTelemetry is available
        def opentelemetry_available?
          defined?(::OpenTelemetry) && ::OpenTelemetry.tracer_provider
        end

        # Create the OpenTelemetry tracer
        #
        # @return [OpenTelemetry::Tracer] The tracer instance
        def create_tracer
          config = Tasker::Configuration.configuration
          ::OpenTelemetry.tracer_provider.tracer(
            config.telemetry.service_name,
            config.telemetry.service_version
          )
        end

        # Convert event attributes to OpenTelemetry format
        #
        # @param attributes [Hash] The attributes to convert
        # @return [Hash] OpenTelemetry-compatible attributes
        def convert_attributes_for_otel(attributes)
          result = {}
          config = Tasker::Configuration.configuration
          service_name = config.telemetry.service_name

          # Filter sensitive data first
          filtered_attributes = filter_sensitive_attributes(attributes)

          # Ensure attributes are properly formatted for OpenTelemetry
          filtered_attributes.each do |key, value|
            # Skip exception_object as it can't be properly serialized
            next if key == :exception_object

            # Use the configured service name as prefix for all attributes
            attr_prefix = "#{service_name}."
            attr_key = key.to_s.start_with?(attr_prefix) ? key.to_s : "#{attr_prefix}#{key}"

            # Convert values based on their type
            result[attr_key] = convert_value_for_otel(value)
          end

          result
        end

        private

        # Convert value to OpenTelemetry-compatible format
        #
        # @param value [Object] The value to convert
        # @return [String] OpenTelemetry-compatible value
        def convert_value_for_otel(value)
          case value
          when Hash, Array
            value.to_json
          when nil
            ''
          else
            value.to_s
          end
        end

        # Set the span status based on the event status
        #
        # @param span [OpenTelemetry::Trace::Span] The span to set status on
        # @param status [Symbol] The status (:ok or :error)
        # @param attributes [Hash] The event attributes (for error message)
        def set_span_status(span, status, attributes)
          return unless defined?(::OpenTelemetry::Trace::Status)

          if status == :error
            error_msg = attributes[:error] || attributes[:error_message] || 'Unknown error'
            span.status = ::OpenTelemetry::Trace::Status.error(error_msg)
          elsif status == :ok
            span.status = ::OpenTelemetry::Trace::Status.ok
          end
        rescue StandardError => e
          Rails.logger.debug { "Failed to set span status: #{e.message}" }
        end

        # Filter sensitive data from attributes
        #
        # @param attributes [Hash] The attributes to filter
        # @return [Hash] The filtered attributes
        def filter_sensitive_attributes(attributes)
          filter = Tasker::Configuration.configuration.telemetry.parameter_filter
          return attributes unless filter

          filtered_data = {}
          attributes.each do |key, value|
            filtered_data[key] = if key == :exception_object
                                   # Skip exception objects for filtering but preserve them
                                   value
                                 else
                                   filter.filter_param(key.to_s, value)
                                 end
          end

          filtered_data
        end

        # Get a hash of active spans for tasks
        #
        # @return [Hash<String, OpenTelemetry::Trace::Span>] Task spans
        def task_spans
          @task_spans ||= {}
        end

        # Store a span for a task
        #
        # @param task_id [String, Integer] The task ID
        # @param span [OpenTelemetry::Trace::Span] The span to store
        def store_task_span(task_id, span)
          return unless task_id && span

          task_spans[task_id.to_s] = span
        end

        # Get a span for a task
        #
        # @param task_id [String, Integer] The task ID
        # @return [OpenTelemetry::Trace::Span, nil] The span or nil if not found
        def get_task_span(task_id)
          return nil unless task_id

          task_spans[task_id.to_s]
        end

        # Remove a span for a task
        #
        # @param task_id [String, Integer] The task ID
        def remove_task_span(task_id)
          return unless task_id

          task_spans.delete(task_id.to_s)
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
          return timestamp.to_time if timestamp.is_a?(Time) || timestamp.is_a?(DateTime)
          if timestamp.is_a?(String) && timestamp.match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
            return Time.zone.parse(timestamp)
          end

          nil
        rescue StandardError
          nil
        end
      end
    end
  end
end
