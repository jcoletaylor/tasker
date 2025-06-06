# frozen_string_literal: true

module Tasker
  module Events
    module Subscribers
      # BaseSubscriber provides a clean foundation for creating custom event subscribers
      #
      # This class extracts common patterns from TelemetrySubscriber and provides:
      # - Declarative subscription registration via class methods
      # - Automatic method routing from event names to handler methods
      # - Defensive payload handling with safe accessors
      # - Easy integration with the Tasker event system
      # - Metrics collection helper methods for common patterns
      #
      # Usage:
      #   class OrderNotificationSubscriber < Tasker::Events::Subscribers::BaseSubscriber
      #     subscribe_to :task_completed, :step_failed
      #
      #     def handle_task_completed(event)
      #       OrderMailer.completion_email(event[:task_id]).deliver_later
      #     end
      #
      #     def handle_step_failed(event)
      #       AlertService.notify("Step failed: #{event[:step_name]}")
      #     end
      #   end
      #
      #   # Register the subscriber
      #   OrderNotificationSubscriber.subscribe(Tasker::Events::Publisher.instance)
      class BaseSubscriber
        class_attribute :subscribed_events, instance_writer: false, default: []
        class_attribute :event_filter, instance_writer: false

        def initialize(name: nil, events: nil, config: {})
          @subscription_name = name
          @subscription_config = config

          # If events are provided via constructor (from YAML), add them to subscribed events
          return if events.blank?

          current_events = self.class.subscribed_events || []
          self.class.subscribed_events = (current_events + Array(events)).uniq
        end

        class << self
          # Declarative method to register events this subscriber cares about
          #
          # @param events [Array<Symbol, String>] Event names to subscribe to
          # @return [void]
          #
          # Example:
          #   subscribe_to :task_completed, :step_failed
          #   subscribe_to 'order.created', 'payment.processed'
          def subscribe_to(*events)
            # Accumulate events instead of replacing them
            current_events = subscribed_events || []
            self.subscribed_events = (current_events + events.map(&:to_s)).uniq
          end

          # Set a filter for events (optional)
          #
          # @param filter_proc [Proc] A proc that returns true for events to process
          # @return [void]
          #
          # Example:
          #   filter_events { |event_name| event_name.include?('order') }
          def filter_events(&filter_proc)
            self.event_filter = filter_proc
          end

          # Subscribe this subscriber to a publisher
          #
          # @param publisher [Tasker::Events::Publisher] The event publisher
          # @return [BaseSubscriber] The subscriber instance
          def subscribe(publisher)
            subscriber = new
            subscriber.subscribe_to_publisher(publisher)
            subscriber
          end
        end

        # Subscribe to all events defined by the class
        #
        # @param publisher [Tasker::Events::Publisher] The event publisher
        # @return [void]
        def subscribe_to_publisher(publisher)
          event_subscriptions.each do |event_constant, handler_method|
            # Apply filtering if defined
            next unless should_handle_event?(event_constant)

            # Subscribe to the event with automatic method routing
            # This will fail fast if the event doesn't exist, which is the correct behavior
            publisher.subscribe(event_constant, &method(handler_method))
          end
        end

        protected

        # Check if an event is a custom event (not a system constant)
        #
        # @param event_constant [String] The event constant or name
        # @return [Boolean] Whether it's a custom event
        def custom_event?(event_constant)
          event_str = event_constant.to_s
          event_str.exclude?('Tasker::Constants::') && event_str.include?('.')
        end

        # Get event subscriptions mapping for this subscriber
        #
        # This method maps event constants to handler methods using naming conventions.
        # Override this method to customize the mapping.
        #
        # @return [Hash] Mapping of event constants to handler method symbols
        def event_subscriptions
          @event_subscriptions ||= build_event_subscriptions
        end

        # Build event subscriptions using explicit constants
        #
        # @return [Hash] Mapping of event constants to handler method symbols
        def build_event_subscriptions
          subscriptions = {}

          (self.class.subscribed_events || []).each do |event_name|
            # Convert developer-friendly name to internal constant
            internal_constant = resolve_internal_event_constant(event_name)

            # Generate handler method name: order.processed -> handle_order_processed
            handler_method = generate_handler_method_name(event_name)

            # Only add if the handler method exists
            if respond_to?(handler_method, true)
              subscriptions[internal_constant] = handler_method
            else
              Rails.logger.warn("#{self.class.name}: Handler method #{handler_method} not found for event #{event_name}")
            end
          end

          subscriptions
        end

        # Resolve developer-friendly event name to internal constant
        #
        # This handles the transparent namespace mapping:
        # - "order.processed" -> "custom.order.processed" (for custom events)
        # - "task.completed" -> "task.completed" (for system events)
        #
        # @param event_name [String] The developer-friendly event name
        # @return [String] The internal event constant
        def resolve_internal_event_constant(event_name)
          event_str = event_name.to_s

          # Check if it's already an internal constant (starts with system prefixes)
          system_prefixes = %w[task. step. workflow. observability.]
          if system_prefixes.any? { |prefix| event_str.start_with?(prefix) }
            return event_str # It's a system event, use as-is
          end

          # Check if it's already prefixed with custom.
          if event_str.start_with?('custom.')
            return event_str # Already internal format
          end

          # Assume it's a custom event and add the prefix
          "custom.#{event_str}"
        end

        # Generate handler method name from event name
        #
        # @param event_name [String] The event name (should be consistent format)
        # @return [Symbol] The handler method name
        def generate_handler_method_name(event_name)
          # Convert dots to underscores and prefix with handle_
          # Examples:
          #   'task.completed' -> :handle_task_completed
          #   'step.failed' -> :handle_step_failed
          #   'custom.event' -> :handle_custom_event
          clean_name = event_name.to_s.tr('.', '_').underscore
          :"handle_#{clean_name}"
        end

        # Check if this subscriber should handle the given event
        #
        # @param event_constant [String] The event constant
        # @return [Boolean] Whether to handle this event
        def should_handle_event?(event_constant)
          # Apply class-level filter if defined
          return false if self.class.event_filter && !self.class.event_filter.call(event_constant)

          # Apply instance-level filtering (override in subclasses)
          should_process_event?(event_constant)
        end

        # Instance-level event filtering (override in subclasses)
        #
        # @param event_constant [String] The event constant
        # @return [Boolean] Whether to handle this event
        def should_process_event?(_event_constant)
          true # Process all events by default
        end

        # Safe accessor for event payload keys with fallback values
        #
        # @param event [Hash, Dry::Events::Event] The event payload or event object
        # @param key [Symbol, String] The key to access
        # @param default [Object] The default value if key is missing
        # @return [Object] The value or default
        def safe_get(event, key, default = nil)
          return default if event.nil?

          # Handle Dry::Events::Event objects
          if event.respond_to?(:payload)
            payload = event.payload
            return payload.fetch(key.to_sym) { payload.fetch(key.to_s, default) }
          end

          # Handle plain hash events
          event.fetch(key.to_sym) do
            event.fetch(key.to_s, default)
          end
        end

        # Extract core attributes common to most events
        #
        # @param event [Hash, Dry::Events::Event] The event payload or event object
        # @return [Hash] Core attributes
        def extract_core_attributes(event)
          {
            task_id: safe_get(event, :task_id, 'unknown'),
            step_id: safe_get(event, :step_id),
            event_timestamp: safe_get(event, :timestamp, Time.current).to_s
          }.compact
        end

        # Extract step-specific attributes (for TelemetrySubscriber compatibility)
        #
        # @param event [Hash, Dry::Events::Event] The event payload or event object
        # @return [Hash] Step attributes
        def extract_step_attributes(event)
          extract_core_attributes(event).merge(
            step_id: safe_get(event, :step_id),
            step_name: safe_get(event, :step_name, 'unknown_step')
          ).compact
        end

        # ===============================
        # METRICS COLLECTION HELPERS
        # ===============================
        # These methods make it easy to extract common metrics data from events

        # Extract timing metrics from completion events
        #
        # @param event [Hash, Dry::Events::Event] The event payload
        # @return [Hash] Timing metrics with default values
        #
        # Example:
        #   timing = extract_timing_metrics(event)
        #   StatsD.histogram('tasker.task.duration', timing[:execution_duration])
        #   StatsD.gauge('tasker.task.step_count', timing[:step_count])
        def extract_timing_metrics(event)
          {
            execution_duration: safe_get(event, :execution_duration, 0.0).to_f,
            started_at: safe_get(event, :started_at),
            completed_at: safe_get(event, :completed_at),
            step_count: safe_get(event, :total_steps, 0).to_i,
            completed_steps: safe_get(event, :completed_steps, 0).to_i,
            failed_steps: safe_get(event, :failed_steps, 0).to_i
          }
        end

        # Extract error metrics from failure events
        #
        # @param event [Hash, Dry::Events::Event] The event payload
        # @return [Hash] Error metrics with categorization
        #
        # Example:
        #   error = extract_error_metrics(event)
        #   StatsD.increment('tasker.errors', tags: ["error_type:#{error[:error_type]}"])
        def extract_error_metrics(event)
          {
            error_message: safe_get(event, :error_message, 'unknown_error'),
            error_class: safe_get(event, :exception_class, 'UnknownError'),
            error_type: categorize_error(safe_get(event, :exception_class)),
            attempt_number: safe_get(event, :attempt_number, 1).to_i,
            is_retryable: safe_get(event, :retryable, false),
            final_failure: safe_get(event, :attempt_number, 1).to_i >= safe_get(event, :retry_limit, 1).to_i
          }
        end

        # Extract performance metrics for operational monitoring
        #
        # @param event [Hash, Dry::Events::Event] The event payload
        # @return [Hash] Performance metrics
        #
        # Example:
        #   perf = extract_performance_metrics(event)
        #   StatsD.histogram('tasker.memory_usage', perf[:memory_usage])
        def extract_performance_metrics(event)
          {
            memory_usage: safe_get(event, :memory_usage, 0).to_i,
            cpu_time: safe_get(event, :cpu_time, 0.0).to_f,
            queue_time: safe_get(event, :queue_time, 0.0).to_f,
            processing_time: safe_get(event, :processing_time, 0.0).to_f,
            retry_delay: safe_get(event, :retry_delay, 0.0).to_f
          }
        end

        # Extract business metrics tags for categorization
        #
        # @param event [Hash, Dry::Events::Event] The event payload
        # @return [Array<String>] Array of tag strings for metrics systems
        #
        # Example:
        #   tags = extract_metric_tags(event)
        #   StatsD.increment('tasker.task.completed', tags: tags)
        def extract_metric_tags(event)
          tags = []

          # Core entity tags
          task_name = safe_get(event, :task_name)
          tags << "task:#{task_name}" if task_name && task_name != 'unknown'

          step_name = safe_get(event, :step_name)
          tags << "step:#{step_name}" if step_name && step_name != 'unknown_step'

          # Environment and source tags
          tags << "environment:#{Rails.env}" if defined?(Rails)
          tags << "source:#{safe_get(event, :source_system)}" if safe_get(event, :source_system)

          # Status and retry tags
          tags << "retryable:#{safe_get(event, :retryable)}" if safe_get(event, :retryable)
          tags << "attempt:#{safe_get(event, :attempt_number)}" if safe_get(event, :attempt_number)

          # Priority and business context
          tags << "priority:#{safe_get(event, :priority)}" if safe_get(event, :priority)

          tags.compact
        end

        # Create metric name with consistent naming convention
        #
        # @param base_name [String] The base metric name
        # @param event_type [String] The event type (completed, failed, etc.)
        # @return [String] Standardized metric name
        #
        # Example:
        #   metric_name = build_metric_name('tasker.task', 'completed')
        #   # => 'tasker.task.completed'
        def build_metric_name(base_name, event_type)
          "#{base_name}.#{event_type}".squeeze('.')
        end

        # Extract numeric value safely for metrics
        #
        # @param event [Hash, Dry::Events::Event] The event payload
        # @param key [Symbol, String] The key to extract
        # @param default [Numeric] The default value
        # @return [Numeric] The numeric value
        #
        # Example:
        #   duration = extract_numeric_metric(event, :execution_duration, 0.0)
        #   StatsD.histogram('task.duration', duration)
        def extract_numeric_metric(event, key, default = 0)
          value = safe_get(event, key, default)

          # Handle nil values and non-numeric types
          return default if value.nil? || !value.respond_to?(:to_f)

          # Try to convert to float
          converted = value.to_f

          # Check if this was a valid numeric conversion
          # For strings that can't convert, to_f returns 0.0
          return default if converted == 0.0 && value.is_a?(String) && value !~ /\A\s*0*(\.0*)?\s*\z/

          converted
        end

        private

        # Categorize error types for metrics tagging
        #
        # @param error_class [String] The exception class name
        # @return [String] Categorized error type
        def categorize_error(error_class)
          return 'unknown' if error_class.blank?

          case error_class.to_s
          when /Timeout/i, /TimeoutError/i
            'timeout'
          when /Connection/i, /Network/i
            'network'
          when /NotFound/i, /Missing/i, /404/
            'not_found'
          when /Unauthorized/i, /Forbidden/i, /401/, /403/
            'auth'
          when /RateLimit/i, /TooManyRequests/i, /429/
            'rate_limit'
          when /BadRequest/i, /Invalid/i, /400/
            'client_error'
          when /ServerError/i, /InternalError/i, /500/
            'server_error'
          when /StandardError/i, /RuntimeError/i
            'runtime'
          else
            'other'
          end
        end
      end
    end
  end
end
