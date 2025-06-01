# frozen_string_literal: true

module Tasker
  # Handles instrumentation setup and configuration for Tasker
  #
  # This module provides telemetry capabilities using ActiveSupport::Notifications
  # and integrates with OpenTelemetry when available. It handles event subscription,
  # span creation, attribute conversion, and sensitive data filtering.
  module Instrumentation
    class << self
      # ✅ FIX: Implement missing record_event method expected by telemetry system
      # This method provides a simple telemetry interface for recording metrics
      #
      # @param metric_name [String] The name of the metric to record
      # @param attributes [Hash] Additional attributes/dimensions for the metric
      # @return [void]
      def record_event(metric_name, attributes = {})
        # Simple implementation: log the metric
        # In production, this could integrate with StatsD, DataDog, etc.
        Rails.logger.debug do
          "[Tasker::Instrumentation] Metric: #{metric_name}, Attributes: #{attributes.inspect}"
        end

        # Also fire as an ActiveSupport notification for consistency
        ActiveSupport::Notifications.instrument("tasker.metric.#{metric_name}", attributes)
      rescue StandardError => e
        # Prevent telemetry errors from breaking the application
        Rails.logger.warn("Failed to record telemetry metric #{metric_name}: #{e.message}")
      end

      # Subscribe to all Tasker events
      #
      # Sets up event subscribers to capture telemetry data for logging
      # and tracing purposes. Delegates to appropriate handlers based on
      # event name and type.
      #
      # @return [void]
      def subscribe
        # Skip if already subscribed
        return if @subscribed

        # Subscribe to all Tasker events using ActiveSupport::Notifications
        ActiveSupport::Notifications.subscribe(/^tasker\./) do |name, started, finished, unique_id, payload|
          # Delegate to appropriate handler
          handle_event(name, started, finished, unique_id, payload)
        end

        # You can also have specific subscribers for different event types if needed
        subscribe_to_opentelemetry
        subscribe_to_logger

        # Mark as subscribed to prevent duplicate subscriptions
        @subscribed = true
      end

      # Subscribe to events and send them to OpenTelemetry
      #
      # Sets up OpenTelemetry instrumentation for Tasker events when
      # OpenTelemetry is available.
      #
      # @return [void]
      def subscribe_to_opentelemetry
        return unless defined?(::OpenTelemetry)

        # Use monotonic subscription for more accurate timing
        ActiveSupport::Notifications.monotonic_subscribe(/^tasker\./) do |name, started, finished, _unique_id, payload|
          # Get the short event name without namespace
          event_name = name.sub(/^tasker\./, '')

          # Create span or add event to current span
          handle_otel_event(event_name, started, finished, payload)
        end
      end

      # Subscribe to events and log them
      #
      # Sets up logging for all Tasker events, including timing information
      # and filtered payload data.
      #
      # @return [void]
      def subscribe_to_logger
        ActiveSupport::Notifications.subscribe(/^tasker\./) do |name, started, finished, _unique_id, payload|
          duration = ((finished - started) * 1000).round(2)
          event_name = name.sub(/^tasker\./, '')
          service_name = Tasker::Configuration.configuration.otel_telemetry_service_name

          # Filter sensitive data before logging
          filtered_payload = filter_sensitive_data(payload)

          # Log the event
          Rails.logger.debug do
            "[#{service_name.capitalize}] #{event_name} (#{duration}ms) #{filtered_payload.inspect}"
          end
        end
      end

      private

      # Handle OpenTelemetry integration for a specific event
      #
      # @param event [String] The event name
      # @param _started [Time] When the event started
      # @param _finished [Time] When the event finished
      # @param payload [Hash] The event payload
      # @return [void]
      def handle_otel_event(event, _started, _finished, payload)
        return unless defined?(::OpenTelemetry)

        # Get OpenTelemetry tracer
        config = Tasker::Configuration.configuration
        tracer = ::OpenTelemetry.tracer_provider.tracer(
          config.otel_telemetry_service_name,
          config.otel_telemetry_service_version
        )

        # Strip metric prefix if present to get the original event name
        clean_event = event.sub(/^metric\.tasker\./, '')

        # Dispatch to appropriate handler based on event type
        case clean_event
        when Tasker::Constants::TaskEvents::START_REQUESTED, Tasker::Constants::TaskEvents::INITIALIZE_REQUESTED
          handle_task_start(tracer, event, payload)
        when Tasker::Constants::TaskEvents::COMPLETED, Tasker::Constants::TaskEvents::FAILED
          handle_task_completion(tracer, event, payload)
        when Tasker::Constants::ObservabilityEvents::Step::HANDLE
          handle_step_event(tracer, event, payload)
        else
          handle_generic_event(tracer, event, payload)
        end
      rescue StandardError => e
        # Prevent errors in instrumentation from breaking the application
        Rails.logger.error("Error in OpenTelemetry instrumentation: #{e.message}")
        Rails.logger.debug(e.backtrace.join("\n")) if Rails.logger.debug?
      end

      # Handle task start events
      #
      # @param tracer [OpenTelemetry::Tracer] The OpenTelemetry tracer
      # @param event [String] The event name
      # @param payload [Hash] The event payload
      # @return [void]
      def handle_task_start(tracer, event, payload)
        # Start a root span for the event type, not the task name
        span = tracer.start_root_span(event,
                                      attributes: convert_attributes(payload))
        span.add_event(event, attributes: convert_attributes(payload))

        # Store the span for the task
        store_task_span(payload[:task_id], span)
      end

      # Handle task completion events (complete or error)
      #
      # @param tracer [OpenTelemetry::Tracer] The OpenTelemetry tracer
      # @param event [String] The event name
      # @param payload [Hash] The event payload
      # @return [void]
      def handle_task_completion(tracer, event, payload)
        # End the task span
        span = get_task_span(payload[:task_id])
        if span
          span.add_event(event, attributes: convert_attributes(payload))

          # Set appropriate status
          set_span_status(span, event, payload)

          span.finish
          remove_task_span(payload[:task_id])
        else
          # Just create a span if we don't have a parent task span
          tracer.in_span(event, attributes: convert_attributes(payload)) do |_new_span|
            # Nothing extra needed here
          end
        end
      end

      # Set the span status based on the event
      #
      # @param span [OpenTelemetry::Trace::Span] The span to set status on
      # @param event [String] The event name
      # @param payload [Hash] The event payload
      # @return [void]
      def set_span_status(span, event, payload)
        if event == Tasker::Constants::TaskEvents::FAILED
          # For testing compatibility, don't directly set status
          if defined?(::OpenTelemetry::Trace::Status)
            error_msg = payload[:error] || 'Task failed'
            span.status = begin
              ::OpenTelemetry::Trace::Status.error(error_msg)
            rescue StandardError
              nil
            end
          end
        elsif defined?(::OpenTelemetry::Trace::Status)
          # For testing compatibility, don't directly set status
          span.status = begin
            ::OpenTelemetry::Trace::Status.ok
          rescue StandardError
            nil
          end
        end
      end

      # Handle step events
      #
      # @param tracer [OpenTelemetry::Tracer] The OpenTelemetry tracer
      # @param event [String] The event name
      # @param payload [Hash] The event payload
      # @return [void]
      def handle_step_event(tracer, event, payload)
        # Create a child span for steps using the event name, not step name
        task_span = get_task_span(payload[:task_id])

        if task_span
          # If we have a parent task span, create a child span
          span_context = ::OpenTelemetry::Trace.context_with_span(task_span)

          ::OpenTelemetry::Context.with_current(span_context) do
            tracer.in_span(event, attributes: convert_attributes(payload)) do |step_span|
              step_span.add_event(event, attributes: convert_attributes(payload))
            end
          end
        else
          # Otherwise create a standalone span
          tracer.in_span(event, attributes: convert_attributes(payload)) do |step_span|
            step_span.add_event(event, attributes: convert_attributes(payload))
          end
        end
      end

      # Handle all other generic events
      #
      # @param tracer [OpenTelemetry::Tracer] The OpenTelemetry tracer
      # @param event [String] The event name
      # @param payload [Hash] The event payload
      # @return [void]
      def handle_generic_event(tracer, event, payload)
        # For all other events, add them to the current span or create a new one
        current_span = ::OpenTelemetry::Trace.current_span

        if current_span && current_span != ::OpenTelemetry::Trace::Span::INVALID
          # Add to current span
          current_span.add_event(event, attributes: convert_attributes(payload))
        else
          # Create a new span for the event
          tracer.in_span(event, attributes: convert_attributes(payload)) do |_span|
            # Just the span creation is enough
          end
        end
      end

      # Convert hash payload to OTel-compatible attributes
      #
      # @param payload [Hash] The event payload
      # @return [Hash] OTel-compatible attributes
      def convert_attributes(payload)
        result = {}
        config = Tasker::Configuration.configuration
        service_name = config.otel_telemetry_service_name

        # Filter sensitive data first
        filtered_payload = filter_sensitive_data(payload)

        # Ensure attributes are properly formatted for OpenTelemetry
        filtered_payload.each do |key, value|
          # Skip exception_object as it can't be properly serialized
          next if key == :exception_object

          # Use the configured service name as prefix for all attributes
          attr_prefix = "#{service_name}."
          attr_key = key.to_s.start_with?(attr_prefix) ? key.to_s : "#{attr_prefix}#{key}"

          # Convert values based on their type
          result[attr_key] = case value
                             when Hash, Array
                               value.to_json
                             when nil
                               ''
                             else
                               value.to_s
                             end
        end

        result
      end

      # Handle all events (main dispatcher)
      #
      # @param name [String] The event name
      # @param started [Time] When the event started
      # @param finished [Time] When the event finished
      # @param unique_id [String] The unique ID of the event
      # @param payload [Hash] The event payload
      # @return [void]
      def handle_event(name, started, finished, unique_id, payload)
        # Additional event handling logic can go here
        # This is called for all events
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
      # @return [void]
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
      # @return [void]
      def remove_task_span(task_id)
        return unless task_id

        task_spans.delete(task_id.to_s)
      end

      # Filter sensitive data from a payload
      #
      # @param payload [Hash] The event payload
      # @return [Hash] The filtered payload
      def filter_sensitive_data(payload)
        # Apply parameter filtering if configured
        filter = Tasker::Configuration.configuration.parameter_filter
        if filter
          # Create a new hash to avoid modifying the original payload
          filtered_data = {}

          # Apply filtering to each key/value pair
          payload.each do |key, value|
            # Skip exception_object for filtering as it can't be properly serialized
            # but we want to preserve it in the payload
            if key == :exception_object
              filtered_data[key] = value
            else
              filtered_value = filter.filter_param(key.to_s, value)
              filtered_data[key] = filtered_value
            end
          end

          return filtered_data
        end

        # If no filtering configured, return the original payload
        payload
      end
    end
  end
end
