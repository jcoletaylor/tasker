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
      # - Using centralized event name constants for consistency throughout
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
            # Filter at subscription time instead of runtime for better performance
            publisher.subscribe(event_constant, &method(handler_method)) if should_record_event?(event_constant)
          end
        end

        # Handle task start events
        def handle_task_initialized(event)
          event_constant = Tasker::LifecycleEvents::Events::Task::INITIALIZE

          attributes = extract_core_attributes(event).merge(
            task_name: safe_get(event, :task_name, 'unknown_task'),
            status: safe_get(event, :status, 'initialized')
          )

          record_metric(event_constant, attributes)
        end

        # Handle task start events
        def handle_task_started(event)
          event_constant = Tasker::LifecycleEvents::Events::Task::START

          attributes = extract_core_attributes(event).merge(
            task_name: safe_get(event, :task_name, 'unknown_task')
          )

          record_metric(event_constant, attributes)
        end

        # Handle task completion events
        def handle_task_completed(event)
          event_constant = Tasker::Constants::TaskEvents::COMPLETED

          attributes = extract_core_attributes(event).merge(
            task_name: safe_get(event, :task_name, 'unknown_task'),
            duration: calculate_duration(event),
            total_execution_duration: safe_get(event, :total_execution_duration, 0.0),
            current_execution_duration: safe_get(event, :current_execution_duration, 0.0),
            total_steps: safe_get(event, :total_steps, 0),
            completed_steps: safe_get(event, :completed_steps, 0)
          )

          record_metric(event_constant, attributes)
        end

        # Handle task failure events
        def handle_task_failed(event)
          event_constant = Tasker::Constants::TaskEvents::FAILED

          attributes = extract_core_attributes(event).merge(
            task_name: safe_get(event, :task_name, 'unknown_task'),
            error: safe_get(event, :error_message, safe_get(event, :error, 'Unknown error')),
            exception_class: safe_get(event, :exception_class, 'StandardError'),
            failed_steps: safe_get(event, :failed_steps, 0)
          )

          record_metric(event_constant, attributes)
        end

        # Handle task cancellation events
        def handle_task_cancelled(event)
          # NOTE: We'll need to add this constant when task cancellation is implemented
          event_name = 'task.cancelled'
          return unless should_record_event?(event_name)

          attributes = extract_core_attributes(event).merge(
            task_name: safe_get(event, :task_name, 'unknown_task')
          )

          record_metric(event_name, attributes)
        end

        # Handle step completion events
        def handle_step_completed(event)
          event_constant = Tasker::Constants::StepEvents::COMPLETED

          attributes = extract_step_attributes(event).merge(
            execution_duration: safe_get(event, :execution_duration, 0.0),
            attempt_number: safe_get(event, :attempt_number, 1)
          )

          record_metric(event_constant, attributes)
        end

        # Handle step failure events
        def handle_step_failed(event)
          event_constant = Tasker::Constants::StepEvents::FAILED

          attributes = extract_step_attributes(event).merge(
            error: safe_get(event, :error_message, safe_get(event, :error, 'Unknown error')),
            attempt_number: safe_get(event, :attempt_number, 1),
            exception_class: safe_get(event, :exception_class, 'StandardError'),
            retry_limit: safe_get(event, :retry_limit, 3)
          )

          record_metric(event_constant, attributes)
        end

        # Handle step retry events
        def handle_step_retry(event)
          event_constant = Tasker::Constants::StepEvents::RETRY_REQUESTED
          return unless should_record_event?(event_constant)

          attributes = extract_step_attributes(event).merge(
            attempt_number: safe_get(event, :attempt_number, 1),
            retry_limit: safe_get(event, :retry_limit, 3)
          )

          record_metric(event_constant, attributes)
        end

        # Handle step backoff events
        def handle_step_backoff(event)
          event_constant = Tasker::Constants::ObservabilityEvents::Step::BACKOFF
          return unless should_record_event?(event_constant)

          attributes = extract_step_attributes(event).merge(
            backoff_seconds: safe_get(event, :backoff_seconds, 0),
            backoff_type: safe_get(event, :backoff_type, 'exponential'),
            attempt_number: safe_get(event, :attempt_number, 1)
          )

          record_metric(event_constant, attributes)
        end

        # Handle workflow iteration events
        def handle_workflow_iteration(event)
          # NOTE: We'll need to add this constant when workflow iteration events are implemented
          event_name = 'workflow.iteration'
          return unless should_record_event?(event_name)

          attributes = extract_core_attributes(event).merge(
            iteration: safe_get(event, :iteration, 1)
          )

          record_metric(event_name, attributes)
        end

        # Handle batch processing events
        def handle_batch_processed(event)
          # NOTE: We'll need to add this constant when batch processing events are implemented
          event_name = 'workflow.batch_processed'
          return unless should_record_event?(event_name)

          attributes = extract_core_attributes(event).merge(
            step_count: safe_get(event, :count, safe_get(event, :step_count, 0)),
            processing_mode: safe_get(event, :processing_mode, 'unknown')
          )

          record_metric(event_name, attributes)
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

        # Handle task processing events (task.handle)
        def handle_task_processing(event)
          event_constant = Tasker::Constants::ObservabilityEvents::Task::HANDLE
          return unless should_record_event?(event_constant)

          attributes = extract_core_attributes(event).merge(
            task_name: safe_get(event, :task_name, 'unknown_task')
          )

          record_metric(event_constant, attributes)
        end

        # Handle task enqueue events
        def handle_task_enqueued(event)
          event_constant = Tasker::Constants::ObservabilityEvents::Task::ENQUEUE
          return unless should_record_event?(event_constant)

          attributes = extract_core_attributes(event).merge(
            task_name: safe_get(event, :task_name, 'unknown_task'),
            queue_name: safe_get(event, :queue_name, 'default')
          )

          record_metric(event_constant, attributes)
        end

        # Handle task finalization events
        def handle_task_finalized(event)
          event_constant = Tasker::Constants::ObservabilityEvents::Task::FINALIZE
          return unless should_record_event?(event_constant)

          attributes = extract_core_attributes(event).merge(
            task_name: safe_get(event, :task_name, 'unknown_task'),
            final_status: safe_get(event, :final_status, 'unknown')
          )

          record_metric(event_constant, attributes)
        end

        # Handle step discovery events (step.find_viable)
        def handle_step_discovery(event)
          event_constant = Tasker::Constants::ObservabilityEvents::Step::FIND_VIABLE
          return unless should_record_event?(event_constant)

          attributes = extract_core_attributes(event).merge(
            discovered_steps: safe_get(event, :count, safe_get(event, :step_count, 0)),
            step_names: safe_get(event, :step_names, '')
          )

          record_metric(event_constant, attributes)
        end

        # Handle step processing events (step.handle)
        def handle_step_processing(event)
          event_constant = Tasker::Constants::ObservabilityEvents::Step::HANDLE
          return unless should_record_event?(event_constant)

          attributes = extract_step_attributes(event)
          record_metric(event_constant, attributes)
        end

        # Handle step skip events
        def handle_step_skipped(event)
          event_constant = Tasker::Constants::ObservabilityEvents::Step::SKIP
          return unless should_record_event?(event_constant)

          attributes = extract_step_attributes(event).merge(
            skip_reason: safe_get(event, :skip_reason, 'unknown')
          )

          record_metric(event_constant, attributes)
        end

        # Handle step max retries reached events
        def handle_step_max_retries(event)
          event_constant = Tasker::Constants::ObservabilityEvents::Step::MAX_RETRIES_REACHED
          return unless should_record_event?(event_constant)

          attributes = extract_step_attributes(event).merge(
            attempt_number: safe_get(event, :attempt_number, 1),
            retry_limit: safe_get(event, :retry_limit, 3)
          )

          record_metric(event_constant, attributes)
        end

        # Handle task re-enqueue events (NEW)
        def handle_task_reenqueue_started(event)
          event_constant = Tasker::Constants::WorkflowEvents::TASK_REENQUEUE_STARTED
          return unless should_record_event?(event_constant)

          attributes = extract_core_attributes(event).merge(
            reason: safe_get(event, :reason, 'unknown'),
            current_status: safe_get(event, :current_status, 'unknown')
          )

          record_metric(event_constant, attributes)
        end

        def handle_task_reenqueue_requested(event)
          event_constant = Tasker::Constants::WorkflowEvents::TASK_REENQUEUE_REQUESTED
          return unless should_record_event?(event_constant)

          attributes = extract_core_attributes(event).merge(
            reason: safe_get(event, :reason, 'unknown')
          )

          record_metric(event_constant, attributes)
        end

        def handle_task_reenqueue_failed(event)
          event_constant = Tasker::Constants::WorkflowEvents::TASK_REENQUEUE_FAILED
          return unless should_record_event?(event_constant)

          attributes = extract_core_attributes(event).merge(
            reason: safe_get(event, :reason, 'unknown'),
            error: safe_get(event, :error, 'Unknown error')
          )

          record_metric(event_constant, attributes)
        end

        def handle_task_reenqueue_delayed(event)
          event_constant = Tasker::Constants::WorkflowEvents::TASK_REENQUEUE_DELAYED
          return unless should_record_event?(event_constant)

          attributes = extract_core_attributes(event).merge(
            reason: safe_get(event, :reason, 'unknown'),
            delay_seconds: safe_get(event, :delay_seconds, 0),
            scheduled_for: safe_get(event, :scheduled_for, Time.current.iso8601)
          )

          record_metric(event_constant, attributes)
        end

        # Handle task finalization events (NEW)
        def handle_task_finalization_started(event)
          event_constant = Tasker::Constants::WorkflowEvents::TASK_FINALIZATION_STARTED
          return unless should_record_event?(event_constant)

          attributes = extract_core_attributes(event).merge(
            total_processed_steps: safe_get(event, :total_processed_steps, 0)
          )

          record_metric(event_constant, attributes)
        end

        def handle_task_finalization_completed(event)
          event_constant = Tasker::Constants::WorkflowEvents::TASK_FINALIZATION_COMPLETED
          return unless should_record_event?(event_constant)

          attributes = extract_core_attributes(event).merge(
            final_status: safe_get(event, :final_status, 'unknown')
          )

          record_metric(event_constant, attributes)
        end

        # Handle workflow orchestration events (NEW)
        def handle_workflow_task_started(event)
          event_constant = Tasker::Constants::WorkflowEvents::TASK_STARTED
          return unless should_record_event?(event_constant)

          attributes = extract_core_attributes(event)
          record_metric(event_constant, attributes)
        end

        def handle_workflow_step_completed(event)
          event_constant = Tasker::Constants::WorkflowEvents::STEP_COMPLETED
          return unless should_record_event?(event_constant)

          attributes = extract_step_attributes(event)
          record_metric(event_constant, attributes)
        end

        def handle_viable_steps_discovered(event)
          event_constant = Tasker::Constants::WorkflowEvents::VIABLE_STEPS_DISCOVERED
          return unless should_record_event?(event_constant)

          attributes = extract_core_attributes(event).merge(
            viable_step_count: safe_get(event, :viable_step_count, 0),
            step_names: safe_get(event, :step_names, []).join(',')
          )

          record_metric(event_constant, attributes)
        end

        def handle_steps_execution_started(event)
          event_constant = Tasker::Constants::WorkflowEvents::STEPS_EXECUTION_STARTED
          return unless should_record_event?(event_constant)

          attributes = extract_core_attributes(event).merge(
            step_count: safe_get(event, :step_count, 0),
            processing_mode: safe_get(event, :processing_mode, 'unknown')
          )

          record_metric(event_constant, attributes)
        end

        def handle_steps_execution_completed(event)
          event_constant = Tasker::Constants::WorkflowEvents::STEPS_EXECUTION_COMPLETED
          return unless should_record_event?(event_constant)

          attributes = extract_core_attributes(event).merge(
            processed_step_count: safe_get(event, :processed_step_count, 0),
            processing_mode: safe_get(event, :processing_mode, 'unknown')
          )

          record_metric(event_constant, attributes)
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
        #
        # @param event_identifier [String, Object] Event name or constant
        # @return [Boolean] Whether to record this event
        def should_record_event?(event_identifier)
          # Skip if telemetry is disabled
          return false unless telemetry_enabled?

          # Convert event identifier to string for filtering
          event_name = event_identifier_to_string(event_identifier)

          # Check if this specific event type is filtered out
          filtered_events = telemetry_config[:filtered_events] || []
          filtered_events.exclude?(event_name)
        end

        # Convert event identifier (constant or string) to a standard string format
        #
        # @param event_identifier [String, Object] Event constant or string name
        # @return [String] Standardized event name
        def event_identifier_to_string(event_identifier)
          return event_identifier if event_identifier.is_a?(String)

          # For constants, convert to a standardized string format
          # This creates a mapping like Tasker::Constants::TaskEvents::COMPLETED => 'task.completed'
          case event_identifier.to_s
          when /Tasker::Constants::TaskEvents::(\w+)/
            "task.#{::Regexp.last_match(1).downcase}"
          when /Tasker::Constants::StepEvents::(\w+)/
            "step.#{::Regexp.last_match(1).downcase}"
          when /Tasker::Constants::WorkflowEvents::(\w+)/
            "workflow.#{::Regexp.last_match(1).downcase}"
          when /Tasker::Constants::ObservabilityEvents::Task::(\w+)/
            "task.#{::Regexp.last_match(1).downcase}"
          when /Tasker::Constants::ObservabilityEvents::Step::(\w+)/
            "step.#{::Regexp.last_match(1).downcase}"
          when /Tasker::LifecycleEvents::Events::Task::(\w+)/
            "task.#{::Regexp.last_match(1).downcase}"
          when /Tasker::LifecycleEvents::Events::Step::(\w+)/
            "step.#{::Regexp.last_match(1).downcase}"
          else
            # Fallback: use the constant name directly
            event_identifier.to_s.split('::').last.downcase
          end
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
          elsif event.respond_to?(:has_key?) && event.key?(key.to_s)
            event[key.to_s]
          else
            fallback
          end
        end

        # Record a metric using the instrumentation system
        #
        # @param event_identifier [String, Object] Event constant or string name
        # @param attributes [Hash] Event attributes
        def record_metric(event_identifier, attributes = {})
          return unless defined?(Tasker::Instrumentation)

          # Convert event identifier to metric name
          metric_name = event_identifier_to_metric_name(event_identifier)

          # Filter out nil values to avoid telemetry issues
          clean_attributes = attributes.compact

          if self.class.batching_enabled?
            # Add to buffer for batch processing
            @event_buffer << {
              metric_name: metric_name,
              attributes: clean_attributes,
              recorded_at: Time.current
            }
          else
            # Send immediately
            send_metric(metric_name, clean_attributes)
          end
        rescue StandardError => e
          Rails.logger.error("Failed to record telemetry metric #{event_identifier}: #{e.message}")
        end

        # Convert event identifier to metric name for instrumentation
        #
        # @param event_identifier [String, Object] Event constant or string name
        # @return [String] Metric name with 'tasker.' prefix
        def event_identifier_to_metric_name(event_identifier)
          if event_identifier.is_a?(String)
            "tasker.#{event_identifier}"
          else
            base_name = event_identifier_to_string(event_identifier)
            "tasker.#{base_name}"
          end
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
            end
            Time.zone.parse(timestamp)
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
            Tasker::Constants::ObservabilityEvents::Step::MAX_RETRIES_REACHED => :handle_step_max_retries,

            # NEW: Task re-enqueue events (from TaskReenqueuer)
            Tasker::Constants::WorkflowEvents::TASK_REENQUEUE_STARTED => :handle_task_reenqueue_started,
            Tasker::Constants::WorkflowEvents::TASK_REENQUEUE_REQUESTED => :handle_task_reenqueue_requested,
            Tasker::Constants::WorkflowEvents::TASK_REENQUEUE_FAILED => :handle_task_reenqueue_failed,
            Tasker::Constants::WorkflowEvents::TASK_REENQUEUE_DELAYED => :handle_task_reenqueue_delayed,

            # NEW: Task finalization events (from TaskFinalizer)
            Tasker::Constants::WorkflowEvents::TASK_FINALIZATION_STARTED => :handle_task_finalization_started,
            Tasker::Constants::WorkflowEvents::TASK_FINALIZATION_COMPLETED => :handle_task_finalization_completed,

            # NEW: Workflow orchestration events
            Tasker::Constants::WorkflowEvents::TASK_STARTED => :handle_workflow_task_started,
            Tasker::Constants::WorkflowEvents::STEP_COMPLETED => :handle_workflow_step_completed,
            Tasker::Constants::WorkflowEvents::VIABLE_STEPS_DISCOVERED => :handle_viable_steps_discovered,
            Tasker::Constants::WorkflowEvents::STEPS_EXECUTION_STARTED => :handle_steps_execution_started,
            Tasker::Constants::WorkflowEvents::STEPS_EXECUTION_COMPLETED => :handle_steps_execution_completed
          }.freeze
        end
      end
    end
  end
end
