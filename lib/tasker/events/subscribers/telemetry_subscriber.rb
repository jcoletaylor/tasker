# frozen_string_literal: true

require_relative '../../constants'

module Tasker
  module Events
    module Subscribers
      # TelemetrySubscriber handles telemetry events for observability
      #
      # This subscriber demonstrates dry-events best practices by:
      # - Keeping event handlers simple and focused
      # - Using minimal ceremony for event processing
      # - Integrating with existing instrumentation
      # - Providing defensive handling for missing payload keys
      # - Optimized event collection with batching and filtering
      # - Using centralized event name constants for consistency
      class TelemetrySubscriber
        # Buffer for batch event collection (if enabled)
        attr_reader :event_buffer, :last_flush_time

        def initialize
          @event_buffer = []
          @last_flush_time = Time.current
          @memoized_attributes = {}
        end

        # Subscribe to all events we care about
        #
        # @param publisher [Tasker::Events::Publisher] The event publisher
        def self.subscribe(publisher)
          subscriber = new
          subscriber.subscribe_to_all_events(publisher)
          # Start the batch flusher if batching is enabled
          subscriber.start_batch_flusher if batching_enabled?
        end

        # Subscribe to all relevant events using a mapping approach
        #
        # @param publisher [Tasker::Events::Publisher] The event publisher
        def subscribe_to_all_events(publisher)
          event_subscriptions.each do |event_constant, handler_method|
            publisher.subscribe(event_constant, &method(handler_method))
          end
        end

        # Handle task start events
        def handle_task_started(event)
          return unless should_record_event?('task.started')

          attributes = extract_core_attributes(event).merge(
            task_name: safe_get(event, :task_name, 'unknown_task')
          )

          record_metric('task.started', attributes)
        end

        # Handle task completion events
        def handle_task_completed(event)
          return unless should_record_event?('task.completed')

          attributes = extract_core_attributes(event).merge(
            task_name: safe_get(event, :task_name, 'unknown_task'),
            duration: calculate_duration(event),
            total_execution_duration: safe_get(event, :total_execution_duration, 0.0),
            current_execution_duration: safe_get(event, :current_execution_duration, 0.0),
            total_steps: safe_get(event, :total_steps, 0),
            completed_steps: safe_get(event, :completed_steps, 0)
          )

          record_metric('task.completed', attributes)
        end

        # Handle task failure events
        def handle_task_failed(event)
          return unless should_record_event?('task.failed')

          attributes = extract_core_attributes(event).merge(
            task_name: safe_get(event, :task_name, 'unknown_task'),
            error: safe_get(event, :error_message, safe_get(event, :error, 'Unknown error')),
            exception_class: safe_get(event, :exception_class, 'StandardError'),
            failed_steps: safe_get(event, :failed_steps, 0)
          )

          record_metric('task.failed', attributes)
        end

        # Handle task cancellation events
        def handle_task_cancelled(event)
          return unless should_record_event?('task.cancelled')

          attributes = extract_core_attributes(event).merge(
            task_name: safe_get(event, :task_name, 'unknown_task')
          )

          record_metric('task.cancelled', attributes)
        end

        # Handle step start events
        def handle_step_started(event)
          return unless should_record_event?('step.started')

          attributes = extract_step_attributes(event)
          record_metric('step.started', attributes)
        end

        # Handle step completion events
        def handle_step_completed(event)
          return unless should_record_event?('step.completed')

          attributes = extract_step_attributes(event).merge(
            execution_duration: safe_get(event, :execution_duration, 0.0),
            attempt_number: safe_get(event, :attempt_number, 1)
          )

          record_metric('step.completed', attributes)
        end

        # Handle step failure events
        def handle_step_failed(event)
          return unless should_record_event?('step.failed')

          attributes = extract_step_attributes(event).merge(
            error: safe_get(event, :error_message, safe_get(event, :error, 'Unknown error')),
            attempt_number: safe_get(event, :attempt_number, 1),
            exception_class: safe_get(event, :exception_class, 'StandardError'),
            retry_limit: safe_get(event, :retry_limit, 3)
          )

          record_metric('step.failed', attributes)
        end

        # Handle step retry events
        def handle_step_retry(event)
          return unless should_record_event?('step.retry')

          attributes = extract_step_attributes(event).merge(
            attempt_number: safe_get(event, :attempt_number, 1),
            retry_limit: safe_get(event, :retry_limit, 3)
          )

          record_metric('step.retry', attributes)
        end

        # Handle step backoff events
        def handle_step_backoff(event)
          return unless should_record_event?('step.backoff')

          attributes = extract_step_attributes(event).merge(
            backoff_seconds: safe_get(event, :backoff_seconds, 0),
            backoff_type: safe_get(event, :backoff_type, 'exponential'),
            attempt_number: safe_get(event, :attempt_number, 1)
          )

          record_metric('step.backoff', attributes)
        end

        # Handle workflow iteration events
        def handle_workflow_iteration(event)
          return unless should_record_event?('workflow.iteration')

          attributes = extract_core_attributes(event).merge(
            iteration: safe_get(event, :iteration, 1)
          )

          record_metric('workflow.iteration', attributes)
        end

        # Handle batch processing events
        def handle_batch_processed(event)
          return unless should_record_event?('workflow.batch_processed')

          attributes = extract_core_attributes(event).merge(
            step_count: safe_get(event, :count, safe_get(event, :step_count, 0)),
            processing_mode: safe_get(event, :processing_mode, 'unknown')
          )

          record_metric('workflow.batch_processed', attributes)
        end

        # Flush any buffered events (for batch processing)
        def flush_events!
          return if @event_buffer.empty?

          events_to_flush = @event_buffer.dup
          @event_buffer.clear
          @last_flush_time = Time.current

          # Send all buffered events in one batch
          events_to_flush.each do |buffered_event|
            send_metric(buffered_event[:metric_name], buffered_event[:attributes])
          end
        rescue StandardError => e
          Rails.logger.error("Failed to flush telemetry events: #{e.message}")
        end

        # Additional lifecycle event handlers for complete coverage

        # Handle task initialization events
        def handle_task_initialized(event)
          return unless should_record_event?('task.initialized')

          attributes = extract_core_attributes(event).merge(
            task_name: safe_get(event, :task_name, 'unknown_task'),
            status: safe_get(event, :status, 'initialized')
          )

          record_metric('task.initialized', attributes)
        end

        # Handle task processing events (task.handle)
        def handle_task_processing(event)
          return unless should_record_event?('task.processing')

          attributes = extract_core_attributes(event).merge(
            task_name: safe_get(event, :task_name, 'unknown_task')
          )

          record_metric('task.processing', attributes)
        end

        # Handle task enqueue events
        def handle_task_enqueued(event)
          return unless should_record_event?('task.enqueued')

          attributes = extract_core_attributes(event).merge(
            task_name: safe_get(event, :task_name, 'unknown_task'),
            queue_name: safe_get(event, :queue_name, 'default')
          )

          record_metric('task.enqueued', attributes)
        end

        # Handle task finalization events
        def handle_task_finalized(event)
          return unless should_record_event?('task.finalized')

          attributes = extract_core_attributes(event).merge(
            task_name: safe_get(event, :task_name, 'unknown_task'),
            final_status: safe_get(event, :final_status, 'unknown')
          )

          record_metric('task.finalized', attributes)
        end

        # Handle step discovery events (step.find_viable)
        def handle_step_discovery(event)
          return unless should_record_event?('step.discovery')

          attributes = extract_core_attributes(event).merge(
            discovered_steps: safe_get(event, :count, safe_get(event, :step_count, 0)),
            step_names: safe_get(event, :step_names, '')
          )

          record_metric('step.discovery', attributes)
        end

        # Handle step processing events (step.handle)
        def handle_step_processing(event)
          return unless should_record_event?('step.processing')

          attributes = extract_step_attributes(event)
          record_metric('step.processing', attributes)
        end

        # Handle step skip events
        def handle_step_skipped(event)
          return unless should_record_event?('step.skipped')

          attributes = extract_step_attributes(event).merge(
            skip_reason: safe_get(event, :skip_reason, 'unknown')
          )

          record_metric('step.skipped', attributes)
        end

        # Handle step max retries reached events
        def handle_step_max_retries(event)
          return unless should_record_event?('step.max_retries_reached')

          attributes = extract_step_attributes(event).merge(
            attempt_number: safe_get(event, :attempt_number, 1),
            retry_limit: safe_get(event, :retry_limit, 3)
          )

          record_metric('step.max_retries_reached', attributes)
        end

        private

        # Extract core attributes that are common across all events
        def extract_core_attributes(event)
          task_id = safe_get(event, :task_id)

          # Use memoization for frequently accessed attributes
          @memoized_attributes[task_id] ||= {
            task_id: task_id,
            event_timestamp: safe_get(event, :event_timestamp, Time.current.iso8601)
          }
        end

        # Extract step-specific attributes
        def extract_step_attributes(event)
          extract_core_attributes(event).merge(
            step_id: safe_get(event, :step_id),
            step_name: safe_get(event, :step_name, 'unknown_step')
          )
        end

        # Check if we should record this event based on configuration
        def should_record_event?(event_name)
          # Skip if telemetry is disabled
          return false unless telemetry_enabled?

          # Check if this specific event type is filtered out
          filtered_events = telemetry_config[:filtered_events] || []
          !filtered_events.include?(event_name)
        end

        # Check if batching is enabled
        def self.batching_enabled?
          # Get configuration from an instance to access telemetry_config
          config = Tasker.configuration.telemetry_config || {}
          config[:batch_events] || false
        end

        # Get telemetry configuration
        def telemetry_config
          @telemetry_config ||= Tasker.configuration.telemetry_config || {}
        end

        # Check if telemetry is enabled
        def telemetry_enabled?
          Tasker.configuration.enable_telemetry != false
        end

        # Start the batch flusher background task
        def start_batch_flusher
          return unless self.class.batching_enabled?

          flush_interval = telemetry_config[:flush_interval] || 5.seconds

          Thread.new do
            loop do
              sleep(flush_interval)
              flush_events! if should_flush?
            end
          rescue StandardError => e
            Rails.logger.error("Telemetry batch flusher error: #{e.message}")
          end
        end

        # Check if we should flush based on time or buffer size
        def should_flush?
          return false if @event_buffer.empty?

          time_threshold = telemetry_config[:flush_interval] || 5.seconds
          size_threshold = telemetry_config[:buffer_size] || 100

          time_elapsed = Time.current - @last_flush_time
          time_elapsed >= time_threshold || @event_buffer.size >= size_threshold
        end

        # Safely get a value from event payload with optional fallback
        #
        # @param event [Hash] The event payload
        # @param key [Symbol] The key to retrieve
        # @param fallback [Object] The fallback value if key is missing
        # @return [Object] The value or fallback
        def safe_get(event, key, fallback = nil)
          if event.respond_to?(:key?) && event.key?(key)
            event[key]
          elsif event.respond_to?(:has_key?) && event.has_key?(key.to_s)
            event[key.to_s]
          else
            fallback
          end
        end

        # Record a metric using the instrumentation system
        def record_metric(metric_name, attributes = {})
          return unless defined?(Tasker::Instrumentation)

          # Filter out nil values to avoid telemetry issues
          clean_attributes = attributes.compact

          if self.class.batching_enabled?
            # Add to buffer for batch processing
            @event_buffer << {
              metric_name: "tasker.#{metric_name}",
              attributes: clean_attributes,
              recorded_at: Time.current
            }
          else
            # Send immediately
            send_metric("tasker.#{metric_name}", clean_attributes)
          end
        rescue StandardError => e
          Rails.logger.error("Failed to record telemetry metric #{metric_name}: #{e.message}")
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
            if timestamp.match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
              Time.zone.parse(timestamp)
            else
              Time.parse(timestamp)
            end
          else
            nil
          end
        rescue StandardError
          nil
        end

        # Define the mapping between event constants and handler methods
        # This makes the subscription logic clear and maintainable
        #
        # @return [Hash] Mapping of event constants to handler method symbols
        def event_subscriptions
          @event_subscriptions ||= {
            # State events (using modern state machine events for direct mappings)
            Tasker::LifecycleEvents::Events::Task::INITIALIZE => :handle_task_initialized,
            Tasker::LifecycleEvents::Events::Task::START => :handle_task_started,
            Tasker::Constants::TaskEvents::COMPLETED => :handle_task_completed,  # Modern replacement for task.complete
            Tasker::Constants::TaskEvents::FAILED => :handle_task_failed,        # Modern replacement for task.error

            Tasker::Constants::StepEvents::COMPLETED => :handle_step_completed,      # Modern replacement for step.complete
            Tasker::Constants::StepEvents::FAILED => :handle_step_failed,            # Modern replacement for step.error
            Tasker::Constants::StepEvents::RETRY_REQUESTED => :handle_step_retry,    # Modern replacement for step.retry

            # Observability/process events (using new ObservabilityEvents namespace)
            Tasker::Constants::ObservabilityEvents::Task::HANDLE => :handle_task_processing,
            Tasker::Constants::ObservabilityEvents::Task::ENQUEUE => :handle_task_enqueued,
            Tasker::Constants::ObservabilityEvents::Task::FINALIZE => :handle_task_finalized,
            Tasker::Constants::ObservabilityEvents::Step::FIND_VIABLE => :handle_step_discovery,
            Tasker::Constants::ObservabilityEvents::Step::HANDLE => :handle_step_processing,
            Tasker::Constants::ObservabilityEvents::Step::BACKOFF => :handle_step_backoff,
            Tasker::Constants::ObservabilityEvents::Step::SKIP => :handle_step_skipped,
            Tasker::Constants::ObservabilityEvents::Step::MAX_RETRIES_REACHED => :handle_step_max_retries
          }.freeze
        end
      end
    end
  end
end
