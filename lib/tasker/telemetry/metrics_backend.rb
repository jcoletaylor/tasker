# frozen_string_literal: true

require 'concurrent-ruby'
require_relative 'metric_types'

module Tasker
  module Telemetry
    # MetricsBackend provides thread-safe, high-performance native metrics collection
    #
    # This class implements Tasker's core metrics storage system with thread-safe operations,
    # automatic EventRouter integration, and zero-overhead metric collection. It follows
    # the singleton pattern consistent with HandlerFactory and Events::Publisher.
    #
    # The backend supports three core metric types:
    # - Counter: Monotonically increasing values (requests, errors, completions)
    # - Gauge: Values that can go up/down (active connections, queue depth)
    # - Histogram: Statistical distributions (latencies, sizes, durations)
    #
    # @example Basic usage
    #   backend = MetricsBackend.instance
    #   backend.counter('api_requests_total').increment
    #   backend.gauge('active_tasks').set(42)
    #   backend.histogram('task_duration_seconds').observe(1.45)
    #
    # @example EventRouter integration
    #   # Automatic metric collection based on event routing
    #   backend.handle_event('task.completed', { duration: 2.1, status: 'success' })
    #
    class MetricsBackend
      include Singleton

      # Core metric registry storing all active metrics
      # Using ConcurrentHash for thread-safe operations without locks
      # @return [Concurrent::Hash] Thread-safe metric storage
      attr_reader :metrics

      # EventRouter instance for intelligent event routing
      # @return [EventRouter] The configured event router
      attr_reader :event_router

      # Backend creation timestamp for monitoring
      # @return [Time] When this backend was initialized
      attr_reader :created_at

      # Initialize the metrics backend
      #
      # Sets up thread-safe storage and integrates with EventRouter.
      # Called automatically via singleton pattern.
      def initialize
        @metrics = Concurrent::Hash.new
        @event_router = nil # Will be set by EventRouter during configuration
        @created_at = Time.current.freeze
        @metric_creation_lock = Mutex.new
      end

      # Register the EventRouter for intelligent routing
      #
      # This method is called by EventRouter during configuration to enable
      # automatic metric collection based on routing decisions.
      #
      # @param router [EventRouter] The configured event router
      # @return [EventRouter] The registered router
      def register_event_router(router)
        @event_router = router
      end

      # Get or create a counter metric
      #
      # Counters are thread-safe and support only increment operations.
      # They're ideal for counting events, requests, errors, etc.
      #
      # @param name [String] The metric name
      # @param labels [Hash] Optional dimensional labels
      # @return [MetricTypes::Counter] The counter instance
      # @raise [ArgumentError] If name is invalid
      #
      # @example
      #   counter = backend.counter('http_requests_total', endpoint: '/api/tasks')
      #   counter.increment(5)
      def counter(name, **labels)
        get_or_create_metric(name, labels, :counter) do
          MetricTypes::Counter.new(name, labels: labels)
        end
      end

      # Get or create a gauge metric
      #
      # Gauges are thread-safe and support set, increment, and decrement operations.
      # They're ideal for values that fluctuate like connections, queue depth, etc.
      #
      # @param name [String] The metric name
      # @param labels [Hash] Optional dimensional labels
      # @return [MetricTypes::Gauge] The gauge instance
      # @raise [ArgumentError] If name is invalid
      #
      # @example
      #   gauge = backend.gauge('active_connections', service: 'api')
      #   gauge.set(100)
      #   gauge.increment(5)
      def gauge(name, **labels)
        get_or_create_metric(name, labels, :gauge) do
          MetricTypes::Gauge.new(name, labels: labels)
        end
      end

      # Get or create a histogram metric
      #
      # Histograms are thread-safe and provide statistical analysis of observed values.
      # They're ideal for measuring durations, sizes, and distributions.
      #
      # @param name [String] The metric name
      # @param labels [Hash] Optional dimensional labels
      # @param buckets [Array<Numeric>] Optional custom bucket boundaries
      # @return [MetricTypes::Histogram] The histogram instance
      # @raise [ArgumentError] If name is invalid or buckets are malformed
      #
      # @example
      #   histogram = backend.histogram('request_duration_seconds', method: 'POST')
      #   histogram.observe(0.145)
      def histogram(name, buckets: nil, **labels)
        get_or_create_metric(name, labels, :histogram) do
          if buckets
            MetricTypes::Histogram.new(name, labels: labels, buckets: buckets)
          else
            MetricTypes::Histogram.new(name, labels: labels)
          end
        end
      end

      # Handle an event from EventRouter and collect appropriate metrics
      #
      # This method is called by EventRouter when an event should be routed to
      # the metrics backend. It automatically creates and updates metrics based
      # on event type and payload.
      #
      # @param event_name [String] The lifecycle event name
      # @param payload [Hash] Event payload with metric data
      # @return [Boolean] True if metrics were collected successfully
      #
      # @example Automatic usage via EventRouter
      #   # EventRouter calls this automatically:
      #   backend.handle_event('task.completed', {
      #     task_id: '123',
      #     duration: 2.45,
      #     status: 'success'
      #   })
      #
      def handle_event(event_name, payload = {})
        return false unless payload.is_a?(Hash)

        case event_name
        when /\.started$/
          # Task/Step started events -> increment counter
          counter("#{extract_entity_type(event_name)}_started_total", **extract_labels(payload)).increment

        when /\.completed$/
          # Task/Step completed events -> counter + duration histogram
          entity_type = extract_entity_type(event_name)
          labels = extract_labels(payload)

          counter("#{entity_type}_completed_total", **labels).increment

          if (duration = extract_duration(payload))
            histogram("#{entity_type}_duration_seconds", **labels).observe(duration)
          end

        when /\.failed$/
          # Task/Step failed events -> error counter + duration histogram
          entity_type = extract_entity_type(event_name)
          labels = extract_labels(payload)

          counter("#{entity_type}_failed_total", **labels).increment

          if (duration = extract_duration(payload))
            histogram("#{entity_type}_duration_seconds", **labels).observe(duration)
          end

        when /\.cancelled$/
          # Task/Step cancelled events -> cancellation counter
          counter("#{extract_entity_type(event_name)}_cancelled_total", **extract_labels(payload)).increment

        when /workflow\.iteration/
          # Workflow iteration events -> gauge for active tasks
          if payload[:active_task_count]
            gauge('workflow_active_tasks').set(payload[:active_task_count])
          end

          if payload[:iteration_duration]
            histogram('workflow_iteration_duration_seconds').observe(payload[:iteration_duration])
          end

        when /system\.health/
          # System health events -> health gauges
          if payload[:healthy_task_count]
            gauge('system_healthy_tasks').set(payload[:healthy_task_count])
          end

          if payload[:failed_task_count]
            gauge('system_failed_tasks').set(payload[:failed_task_count])
          end
        end

        true
      rescue => e
        # Fail gracefully - metrics collection should never break the application
        warn "MetricsBackend failed to handle event #{event_name}: #{e.message}"
        false
      end

      # Get all registered metrics
      #
      # Returns a thread-safe snapshot of all current metrics for export
      # to monitoring systems like Prometheus.
      #
      # @return [Hash] All metrics keyed by metric key
      def all_metrics
        @metrics.each_with_object({}) do |(key, metric), result|
          result[key] = metric
        end
      end

      # Export all metrics to a format suitable for monitoring systems
      #
      # Provides a comprehensive export of all metric data including
      # metadata, current values, and statistical information.
      #
      # @return [Hash] Comprehensive metric export data
      def export
        {
          timestamp: Time.current,
          backend_created_at: @created_at,
          total_metrics: @metrics.size,
          metrics: all_metrics.transform_values(&:to_h)
        }
      end

      # Get summary statistics about the metrics backend
      #
      # @return [Hash] Backend statistics and health information
      def stats
        metric_types = all_metrics.values.group_by { |m| m.to_h[:type] }

        {
          total_metrics: @metrics.size,
          counter_metrics: metric_types[:counter]&.size || 0,
          gauge_metrics: metric_types[:gauge]&.size || 0,
          histogram_metrics: metric_types[:histogram]&.size || 0,
          backend_uptime: Time.current - @created_at,
          created_at: @created_at
        }
      end

      # Clear all metrics (primarily for testing)
      #
      # @return [Integer] Number of metrics cleared
      def clear!
        cleared_count = @metrics.size
        @metrics.clear
        cleared_count
      end

      private

      # Get or create a metric with thread-safe operations
      #
      # Uses double-checked locking pattern to minimize lock contention
      # while ensuring thread safety during metric creation.
      #
      # @param name [String] Metric name
      # @param labels [Hash] Metric labels
      # @param type [Symbol] Metric type (:counter, :gauge, :histogram)
      # @yield Block that creates the metric instance
      # @return [Object] The metric instance
      def get_or_create_metric(name, labels, type)
        raise ArgumentError, "Metric name cannot be nil or empty" if name.nil? || name.to_s.strip.empty?

        metric_key = build_metric_key(name, labels)

        # Fast path: metric already exists
        existing_metric = @metrics[metric_key]
        return existing_metric if existing_metric

        # Slow path: create new metric with lock
        @metric_creation_lock.synchronize do
          # Double-check pattern: another thread might have created it
          existing_metric = @metrics[metric_key]
          return existing_metric if existing_metric

          # Create and store the new metric
          new_metric = yield
          @metrics[metric_key] = new_metric
          new_metric
        end
      end

      # Build a unique key for metric identification
      #
      # Creates a deterministic key that combines metric name and labels
      # for efficient storage and retrieval.
      #
      # @param name [String] Metric name
      # @param labels [Hash] Metric labels
      # @return [String] Unique metric key
      def build_metric_key(name, labels)
        if labels.empty?
          name.to_s
        else
          # Sort labels for deterministic key generation
          sorted_labels = labels.sort.to_h
          "#{name}#{sorted_labels.inspect}"
        end
      end

      # Extract entity type from event name (task, step, workflow, etc.)
      #
      # @param event_name [String] The lifecycle event name
      # @return [String] The entity type
      def extract_entity_type(event_name)
        # Examples: 'task.completed' -> 'task', 'step.failed' -> 'step'
        event_name.split('.').first || 'unknown'
      end

      # Extract duration value from event payload
      #
      # @param payload [Hash] Event payload
      # @return [Numeric, nil] Duration in seconds, or nil if not present
      def extract_duration(payload)
        duration = payload[:duration] || payload['duration']
        return nil unless duration.is_a?(Numeric)
        duration
      end

      # Extract labels from event payload for dimensional metrics
      #
      # @param payload [Hash] Event payload
      # @return [Hash] Extracted labels for metric dimensions
      def extract_labels(payload)
        labels = {}

        # Common label extractions
        labels[:status] = payload[:status] || payload['status'] if payload[:status] || payload['status']
        labels[:handler] = payload[:handler_class] || payload['handler_class'] if payload[:handler_class] || payload['handler_class']
        labels[:namespace] = payload[:namespace] || payload['namespace'] if payload[:namespace] || payload['namespace']

        # Filter out nil values and ensure string keys
        labels.reject { |_, v| v.nil? }.transform_keys(&:to_s)
      end
    end
  end
end
