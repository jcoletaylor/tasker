# frozen_string_literal: true

require 'concurrent-ruby'
require 'socket'
require_relative 'metric_types'

module Tasker
  module Telemetry
    # MetricsBackend provides thread-safe, high-performance native metrics collection
    #
    # This class implements Tasker's core metrics storage system with thread-safe operations,
    # automatic EventRouter integration, and zero-overhead metric collection. It follows
    # the singleton pattern consistent with HandlerFactory and Events::Publisher.
    #
    # **Phase 4.2.2.3 Enhancement: Hybrid Rails Cache Architecture**
    # The backend now supports cache-agnostic dual storage combining in-memory performance
    # with Rails.cache persistence and cross-container coordination.
    #
    # The backend supports three core metric types:
    # - Counter: Monotonically increasing values (requests, errors, completions)
    # - Gauge: Values that can go up/down (active connections, queue depth)
    # - Histogram: Statistical distributions (latencies, sizes, durations)
    #
    # **Cache Store Compatibility:**
    # - Redis/Memcached: Full coordination with atomic operations and locking
    # - File/Memory stores: Local-only mode with clear degradation messaging
    # - Automatic feature detection with appropriate strategy selection
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
    # @example Cache synchronization
    #   backend.sync_to_cache!  # Periodic background sync
    #   backend.export_distributed_metrics  # Cross-container export
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

      # Cache capabilities detected at initialization
      # @return [Hash] Detected Rails.cache capabilities
      attr_reader :cache_capabilities

      # Selected sync strategy based on cache capabilities
      # @return [Symbol] One of :distributed_atomic, :distributed_basic, :local_only
      attr_reader :sync_strategy

      # Unique instance identifier for distributed coordination
      # @return [String] Hostname-PID identifier for this instance
      attr_reader :instance_id

      # Configuration for cache synchronization
      # @return [Hash] Sync configuration parameters
      attr_reader :sync_config

      # Cache strategy for this instance
      # @return [Tasker::CacheStrategy] The cache strategy for this instance
      attr_reader :cache_strategy

      # Initialize the metrics backend
      #
      # Sets up thread-safe storage, integrates with EventRouter, and configures
      # cache capabilities for hybrid architecture.
      # Called automatically via singleton pattern.
      def initialize
        @metrics = Concurrent::Hash.new
        @event_router = nil
        @local_buffer = []
        @last_sync = Time.current
        @created_at = Time.current.freeze

        # Thread-safe metric creation lock
        @metric_creation_lock = Mutex.new

        # Use unified cache strategy for capability detection
        @cache_strategy = Tasker::CacheStrategy.detect
        @instance_id = @cache_strategy.instance_id
        @sync_strategy = @cache_strategy.coordination_mode

        # Extract capabilities for backward compatibility
        @cache_capabilities = @cache_strategy.export_capabilities
        @sync_config = configure_sync_parameters

        log_cache_strategy_selection
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

      # Synchronize in-memory metrics to Rails.cache using detected strategy
      #
      # This method implements the core cache synchronization logic that adapts
      # to the available Rails.cache store capabilities.
      #
      # @return [Hash] Sync result with success status and metrics count
      #
      # @example Periodic sync (typically called from background job)
      #   result = backend.sync_to_cache!
      #   # => { success: true, synced_metrics: 42, strategy: :distributed_atomic }
      def sync_to_cache!
        return { success: false, error: 'Rails.cache not available' } unless rails_cache_available?

        start_time = Time.current

        case @sync_strategy
        when :distributed_atomic
          result = sync_with_atomic_operations
        when :distributed_basic
          result = sync_with_read_modify_write
        when :local_only
          result = sync_to_local_cache
        else
          return { success: false, error: "Unknown sync strategy: #{@sync_strategy}" }
        end

        final_result = result.merge(
          duration: Time.current - start_time,
          timestamp: Time.current.iso8601,
          instance_id: @instance_id
        )

        # Coordinate with export system
        coordinate_cache_sync(final_result)

        final_result
      rescue StandardError => e
        log_sync_error(e)
        { success: false, error: e.message, timestamp: Time.current.iso8601 }
      end

      # Export metrics with distributed coordination when supported
      #
      # This method aggregates metrics across containers when possible,
      # falls back to local export for limited cache stores.
      #
      # @param include_instances [Boolean] Whether to include per-instance metrics
      # @return [Hash] Export data with aggregated metrics when available
      def export_distributed_metrics(include_instances: false)
        case @sync_strategy
        when :distributed_atomic, :distributed_basic
          aggregate_from_distributed_cache(include_instances: include_instances)
        when :local_only
          export_local_metrics_with_warning
        else
          export # Fallback to standard local export
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
          gauge('workflow_active_tasks').set(payload[:active_task_count]) if payload[:active_task_count]

          if payload[:iteration_duration]
            histogram('workflow_iteration_duration_seconds').observe(payload[:iteration_duration])
          end

        when /system\.health/
          # System health events -> health gauges
          gauge('system_healthy_tasks').set(payload[:healthy_task_count]) if payload[:healthy_task_count]

          gauge('system_failed_tasks').set(payload[:failed_task_count]) if payload[:failed_task_count]
        end

        true
      rescue StandardError => e
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
      def get_or_create_metric(name, labels, _type)
        raise ArgumentError, 'Metric name cannot be nil or empty' if name.nil? || name.to_s.strip.empty?

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
        if payload[:handler_class] || payload['handler_class']
          labels[:handler] =
            payload[:handler_class] || payload['handler_class']
        end
        labels[:namespace] = payload[:namespace] || payload['namespace'] if payload[:namespace] || payload['namespace']

        # Filter out nil values and ensure string keys
        labels.compact.transform_keys(&:to_s)
      end

      # Generate unique instance identifier for distributed coordination
      #
      # @return [String] Hostname-PID identifier
      def generate_instance_id
        hostname = begin
          ENV['HOSTNAME'] || Socket.gethostname
        rescue StandardError
          'unknown'
        end
        "#{hostname}-#{Process.pid}"
      end

      # Configure sync parameters based on strategy and telemetry config
      #
      # @return [Hash] Sync configuration parameters
      def configure_sync_parameters
        base_config = {
          retention_window: 5.minutes,
          export_safety_margin: 1.minute,
          sync_interval: 30.seconds
        }

        # Override with telemetry configuration if available
        if defined?(Tasker.configuration) && Tasker.configuration.telemetry
          telemetry_config = Tasker.configuration.telemetry
          base_config[:retention_window] = (telemetry_config.metrics_retention_hours || 1).hours
        end

        base_config[:export_interval] = base_config[:retention_window] - base_config[:export_safety_margin]
        base_config
      end

      # Synchronize metrics using atomic operations (Redis/Memcached)
      # Synchronize metrics using atomic operations (Redis/advanced stores)
      #
      # **Phase 4.2.2.3.2**: Enhanced atomic synchronization with batch operations,
      # conflict resolution, and performance optimizations for distributed coordination.
      #
      # @return [Hash] Detailed sync result with performance metrics
      def sync_with_atomic_operations
        execute_sync_operation(
          strategy: :distributed_atomic,
          stats_template: { counters: 0, gauges: 0, histograms: 0, conflicts: 0, batches: 0 },
          logger: method(:log_atomic_sync_success)
        ) do |grouped_metrics, sync_stats|
          process_atomic_sync_by_type(grouped_metrics, sync_stats)
        end
      end

      # Synchronize metrics using read-modify-write (basic distributed caches)
      #
      # **Phase 4.2.2.3.2**: Enhanced read-modify-write with retry logic,
      # conflict detection, and optimistic concurrency control for safe updates.
      #
      # @return [Hash] Detailed sync result with retry statistics
      def sync_with_read_modify_write
        execute_sync_operation(
          strategy: :distributed_basic,
          stats_template: { counters: 0, gauges: 0, histograms: 0, retries: 0, conflicts: 0, batches: 0, failed: 0 },
          logger: method(:log_rmw_sync_success)
        ) do |grouped_metrics, sync_stats|
          sync_stats.merge!(sync_with_optimistic_concurrency(grouped_metrics))
        end
      end

      # Create local cache snapshot (memory/file stores)
      #
      # **Phase 4.2.2.3.2**: Enhanced local synchronization with versioned snapshots,
      # efficient serialization, and proper state management for local-only deployment.
      #
      # @return [Hash] Detailed sync result with snapshot information
      def sync_to_local_cache
        execute_local_snapshot_sync
      end

      # Aggregate metrics from distributed cache
      #
      # @param include_instances [Boolean] Include per-instance breakdowns
      # @return [Hash] Aggregated export data
      def aggregate_from_distributed_cache(include_instances: false)
        # Implementation for distributed aggregation
        # This will be expanded in Phase 4.2.2.3.3

        export_data = export
        export_data[:distributed] = true
        export_data[:sync_strategy] = @sync_strategy
        export_data[:note] = 'Distributed aggregation - Phase 4.2.2.3.3'
        export_data
      end

      # Export local metrics with cache limitation warning
      #
      # @return [Hash] Local export with warning
      def export_local_metrics_with_warning
        export_data = export
        export_data[:distributed] = false
        export_data[:sync_strategy] = @sync_strategy
        export_data[:warning] = "Cache store doesn't support distribution - metrics are local-only"
        export_data
      end

      # Build cache key for metric storage following Rails best practices
      #
      # Uses Rails-standard cache key patterns with proper namespacing
      # and supports complex key structures as recommended in the Rails guide.
      #
      # @param metric_key [String] Internal metric key
      # @return [Array] Rails.cache compatible structured key
      def build_cache_key(metric_key)
        # Use structured keys as recommended by Rails caching guide
        # This allows Rails to handle namespacing, size limits, and transformations
        [
          'tasker',
          'metrics',
          @instance_id,
          metric_key
        ]
      end

      # Prepare export data for local cache storage
      #
      # @return [Hash] Serializable export data
      def prepare_local_export_data
        {
          timestamp: Time.current.iso8601,
          instance_id: @instance_id,
          total_metrics: @metrics.size,
          metrics: @metrics.transform_values(&:to_h),
          cache_capabilities: @cache_capabilities
        }
      end

      # Create default metric data for merging
      #
      # @param type [Symbol] Metric type
      # @return [Hash] Default data structure
      def default_metric_data(type)
        case type
        when :counter
          { type: :counter, value: 0 }
        when :gauge
          { type: :gauge, value: 0 }
        when :histogram
          { type: :histogram, count: 0, sum: 0.0, buckets: {} }
        else
          {}
        end
      end

      # Merge metric data for read-modify-write operations
      #
      # @param existing [Hash] Existing cached metric data
      # @param current [Hash] Current in-memory metric data
      # @return [Hash] Merged metric data
      def merge_metric_data(existing, current)
        return current unless existing.is_a?(Hash)

        case current[:type]
        when :counter
          {
            type: :counter,
            value: (existing[:value] || 0) + current[:value],
            labels: current[:labels]
          }
        when :gauge
          # Gauges use most recent value (current instance wins)
          current
        when :histogram
          # Histogram merging - sum the statistics
          {
            type: :histogram,
            count: (existing[:count] || 0) + current[:count],
            sum: (existing[:sum] || 0.0) + current[:sum],
            buckets: merge_histogram_buckets(existing[:buckets] || {}, current[:buckets] || {}),
            labels: current[:labels]
          }
        else
          current
        end
      end

      # Merge histogram bucket data
      #
      # @param existing_buckets [Hash] Existing bucket counts
      # @param current_buckets [Hash] Current bucket counts
      # @return [Hash] Merged bucket counts
      def merge_histogram_buckets(existing_buckets, current_buckets)
        all_buckets = (existing_buckets.keys + current_buckets.keys).uniq
        all_buckets.index_with do |bucket|
          (existing_buckets[bucket] || 0) + (current_buckets[bucket] || 0)
        end
      end

      # **Phase 4.2.2.3.2 Supporting Methods**
      # ====================================

      # Execute a sync operation with common error handling and timing
      #
      # @param strategy [Symbol] Sync strategy identifier
      # @param stats_template [Hash] Initial stats structure
      # @param logger [Method] Logging method for success
      # @yield [grouped_metrics, sync_stats] Block to execute sync logic
      # @return [Hash] Standardized sync result
      def execute_sync_operation(strategy:, stats_template:, logger:)
        start_time = Time.current
        sync_stats = stats_template.dup

        begin
          grouped_metrics = group_metrics_by_type
          yield(grouped_metrics, sync_stats)

          sync_duration = Time.current - start_time
          total_synced = calculate_total_synced_metrics(sync_stats)

          logger.call(sync_stats, sync_duration)

          build_success_result(strategy, total_synced, sync_duration, sync_stats)
        rescue StandardError => e
          log_sync_error(e)
          build_error_result(strategy, e, sync_stats)
        end
      end

      # Process atomic sync operations by metric type
      #
      # @param grouped_metrics [Hash] Metrics grouped by type
      # @param sync_stats [Hash] Statistics accumulator
      def process_atomic_sync_by_type(grouped_metrics, sync_stats)
        # Process counters with true atomic operations
        sync_stats.merge!(sync_atomic_counters(grouped_metrics[:counter])) if grouped_metrics[:counter].any?

        # Process gauges with last-writer-wins strategy
        sync_stats.merge!(sync_distributed_gauges(grouped_metrics[:gauge])) if grouped_metrics[:gauge].any?

        # Process histograms with atomic aggregation
        return unless grouped_metrics[:histogram].any?

        sync_stats.merge!(sync_distributed_histograms(grouped_metrics[:histogram]))
      end

      # Calculate total synced metrics from stats
      #
      # @param sync_stats [Hash] Statistics hash
      # @return [Integer] Total synced metrics count
      def calculate_total_synced_metrics(sync_stats)
        sync_stats.values_at(:counters, :gauges, :histograms).compact.sum
      end

      # Build successful sync result
      #
      # @param strategy [Symbol] Sync strategy
      # @param total_synced [Integer] Total metrics synced
      # @param sync_duration [Float] Duration in seconds
      # @param sync_stats [Hash] Performance statistics
      # @return [Hash] Success result
      def build_success_result(strategy, total_synced, sync_duration, sync_stats)
        {
          success: true,
          strategy: strategy,
          synced_metrics: total_synced,
          duration_ms: (sync_duration * 1000).round(2),
          performance: sync_stats,
          timestamp: Time.current.iso8601
        }
      end

      # Build error sync result
      #
      # @param strategy [Symbol] Sync strategy
      # @param error [Exception] Error that occurred
      # @param sync_stats [Hash] Partial statistics
      # @return [Hash] Error result
      def build_error_result(strategy, error, sync_stats)
        {
          success: false,
          strategy: strategy,
          error: error.message,
          partial_results: sync_stats,
          timestamp: Time.current.iso8601
        }
      end

      # Execute local snapshot synchronization with proper error handling
      #
      # @return [Hash] Detailed sync result with snapshot information
      def execute_local_snapshot_sync
        start_time = Time.current
        sync_stats = { snapshots: 0, metrics_serialized: 0, size_bytes: 0 }

        begin
          snapshot_data = create_versioned_snapshot
          snapshot_keys = build_snapshot_keys
          write_result = write_snapshot_data(snapshot_data, snapshot_keys, sync_stats)

          sync_duration = Time.current - start_time
          log_local_sync_success(sync_stats, sync_duration)

          build_local_sync_result(write_result, sync_duration, sync_stats, snapshot_keys[:primary])
        rescue StandardError => e
          log_sync_error(e)
          build_error_result(:local_only, e, {})
        end
      end

      # Build snapshot cache keys for primary and history storage
      #
      # @return [Hash] Hash containing primary and timestamped keys
      def build_snapshot_keys
        {
          primary: ['tasker', 'metrics', 'snapshot', @instance_id],
          timestamped: ['tasker', 'metrics', 'history', @instance_id, Time.current.to_i]
        }
      end

      # Write snapshot data to cache with redundancy
      #
      # @param snapshot_data [Hash] Snapshot data to write
      # @param snapshot_keys [Hash] Cache keys for storage
      # @param sync_stats [Hash] Statistics accumulator
      # @return [Boolean] Success status of primary write
      def write_snapshot_data(snapshot_data, snapshot_keys, sync_stats)
        # Write primary snapshot with compression awareness
        write_result = Rails.cache.write(snapshot_keys[:primary], snapshot_data,
                                         expires_in: @sync_config[:retention_window])

        if write_result
          update_snapshot_stats(sync_stats, snapshot_data)
          write_history_snapshot(snapshot_data, snapshot_keys[:timestamped], sync_stats)
        end

        write_result
      end

      # Update statistics after successful snapshot write
      #
      # @param sync_stats [Hash] Statistics accumulator
      # @param snapshot_data [Hash] Snapshot data
      def update_snapshot_stats(sync_stats, snapshot_data)
        sync_stats[:snapshots] += 1
        sync_stats[:metrics_serialized] = @metrics.size
        sync_stats[:size_bytes] = estimate_snapshot_size(snapshot_data)
      end

      # Write optional history snapshot for redundancy
      #
      # @param snapshot_data [Hash] Snapshot data
      # @param timestamped_key [Array] Timestamped cache key
      # @param sync_stats [Hash] Statistics accumulator
      def write_history_snapshot(snapshot_data, timestamped_key, sync_stats)
        Rails.cache.write(timestamped_key, snapshot_data,
                          expires_in: @sync_config[:retention_window] / 2)
        sync_stats[:snapshots] += 1
      rescue StandardError
        # History snapshot failure is non-critical
      end

      # Build result for local sync operation
      #
      # @param write_result [Boolean] Primary write success
      # @param sync_duration [Float] Duration in seconds
      # @param sync_stats [Hash] Performance statistics
      # @param primary_key [Array] Primary snapshot key
      # @return [Hash] Local sync result
      def build_local_sync_result(write_result, sync_duration, sync_stats, primary_key)
        {
          success: write_result,
          strategy: :local_only,
          synced_metrics: @metrics.size,
          duration_ms: (sync_duration * 1000).round(2),
          performance: sync_stats,
          snapshot_key: primary_key,
          timestamp: Time.current.iso8601
        }
      end

      # Group metrics by type for optimized batch processing
      #
      # @return [Hash] Metrics grouped by type (:counter, :gauge, :histogram)
      def group_metrics_by_type
        result = { counter: [], gauge: [], histogram: [] }

        @metrics.each do |key, metric|
          metric_data = metric.to_h
          type = metric_data[:type]
          result[type] << [key, metric_data] if result.key?(type)
        end

        result
      end

      # Synchronize counters using atomic operations
      #
      # @param counter_metrics [Array] Array of [key, metric_data] pairs
      # @return [Hash] Sync statistics
      def sync_atomic_counters(counter_metrics)
        stats = { counters: 0, conflicts: 0 }

        counter_metrics.each do |key, metric_data|
          cache_key = build_cache_key(key)

          begin
            # Use atomic increment for true cross-container coordination
            Rails.cache.increment(cache_key, metric_data[:value],
                                  expires_in: @sync_config[:retention_window],
                                  initial: 0)
            stats[:counters] += 1
          rescue StandardError
            stats[:conflicts] += 1
            # Fallback to regular write for non-atomic stores
            Rails.cache.write(cache_key, metric_data,
                              expires_in: @sync_config[:retention_window])
          end
        end

        stats
      end

      # Synchronize gauges with last-writer-wins strategy
      #
      # @param gauge_metrics [Array] Array of [key, metric_data] pairs
      # @return [Hash] Sync statistics
      def sync_distributed_gauges(gauge_metrics)
        stats = { gauges: 0, conflicts: 0 }

        gauge_metrics.each do |key, metric_data|
          cache_key = build_cache_key(key)

          # Add timestamp for conflict resolution
          enhanced_data = metric_data.merge(
            last_update: Time.current.to_f,
            instance_id: @instance_id
          )

          begin
            Rails.cache.write(cache_key, enhanced_data,
                              expires_in: @sync_config[:retention_window])
            stats[:gauges] += 1
          rescue StandardError
            stats[:conflicts] += 1
          end
        end

        stats
      end

      # Synchronize histograms with atomic aggregation
      #
      # @param histogram_metrics [Array] Array of [key, metric_data] pairs
      # @return [Hash] Sync statistics
      def sync_distributed_histograms(histogram_metrics)
        stats = { histograms: 0, conflicts: 0 }

        histogram_metrics.each do |key, metric_data|
          cache_key = build_cache_key(key)

          # Try atomic aggregation first, fallback to merge
          if attempt_atomic_histogram_update(cache_key, metric_data)
            stats[:histograms] += 1
          else
            # Fallback to read-modify-write for histograms
            existing = Rails.cache.read(cache_key) || default_metric_data(:histogram)
            merged = merge_metric_data(existing, metric_data)
            Rails.cache.write(cache_key, merged, expires_in: @sync_config[:retention_window])
            stats[:histograms] += 1
            stats[:conflicts] += 1
          end
        end

        stats
      end

      # Attempt atomic histogram update
      #
      # @param cache_key [Array] Structured cache key
      # @param metric_data [Hash] Histogram metric data
      # @return [Boolean] Success status
      def attempt_atomic_histogram_update(cache_key, metric_data)
        # For stores that support atomic operations, try to update histogram components
        if @cache_capabilities[:atomic_increment]
          count_key = cache_key + ['count']
          sum_key = cache_key + ['sum']

          begin
            Rails.cache.increment(count_key, metric_data[:count], initial: 0,
                                                                  expires_in: @sync_config[:retention_window])
            Rails.cache.increment(sum_key, metric_data[:sum], initial: 0.0,
                                                              expires_in: @sync_config[:retention_window])

            # Update buckets individually
            metric_data[:buckets]&.each do |bucket, count|
              bucket_key = cache_key + ['buckets', bucket.to_s]
              Rails.cache.increment(bucket_key, count, initial: 0,
                                                       expires_in: @sync_config[:retention_window])
            end

            return true
          rescue StandardError
            return false
          end
        end
        false
      end

      # Synchronize with optimistic concurrency control
      #
      # @param grouped_metrics [Hash] Metrics grouped by type
      # @return [Hash] Combined sync statistics
      def sync_with_optimistic_concurrency(grouped_metrics)
        stats = initialize_concurrency_stats

        grouped_metrics.each do |type, metrics|
          process_metrics_with_concurrency_control(type, metrics, stats)
        end

        stats
      end

      # Initialize statistics for concurrency control
      #
      # @return [Hash] Initial statistics structure
      def initialize_concurrency_stats
        { counters: 0, gauges: 0, histograms: 0, retries: 0, conflicts: 0, failed: 0 }
      end

      # Process metrics of a specific type with concurrency control
      #
      # @param type [Symbol] Metric type (:counter, :gauge, :histogram)
      # @param metrics [Array] Array of [key, metric_data] pairs
      # @param stats [Hash] Statistics accumulator
      def process_metrics_with_concurrency_control(type, metrics, stats)
        metrics.each do |key, metric_data|
          success = sync_single_metric_with_retry(type, key, metric_data, stats)
          stats[:failed] += 1 unless success
        end
      end

      # Sync a single metric with retry logic
      #
      # @param type [Symbol] Metric type
      # @param key [String] Metric key
      # @param metric_data [Hash] Metric data
      # @param stats [Hash] Statistics accumulator
      # @return [Boolean] Success status
      def sync_single_metric_with_retry(type, key, metric_data, stats)
        cache_key = build_cache_key(key)
        max_retries = 3
        retry_count = 0

        while retry_count < max_retries
          success = attempt_optimistic_write(type, cache_key, metric_data, stats)
          return true if success

          retry_count += 1
          stats[:retries] += 1
          sleep(calculate_backoff_delay(retry_count))
        end

        false
      end

      # Attempt a single optimistic write operation
      #
      # @param type [Symbol] Metric type
      # @param cache_key [Array] Cache key
      # @param metric_data [Hash] Metric data
      # @param stats [Hash] Statistics accumulator
      # @return [Boolean] Success status
      def attempt_optimistic_write(type, cache_key, metric_data, stats)
        # Read current value
        existing = Rails.cache.read(cache_key) || default_metric_data(type)

        # Merge with current data
        merged = merge_metric_data(existing, metric_data)

        # Attempt to write (this could fail if another process updates)
        if Rails.cache.write(cache_key, merged, expires_in: @sync_config[:retention_window])
          increment_metric_type_stats(type, stats)
          true
        else
          false
        end
      rescue StandardError
        stats[:conflicts] += 1
        false
      end

      # Increment statistics for successful metric sync
      #
      # @param type [Symbol] Metric type
      # @param stats [Hash] Statistics accumulator
      def increment_metric_type_stats(type, stats)
        plural_type = convert_type_to_plural(type)
        stats[plural_type] += 1
      end

      # Convert singular metric type to plural stats key
      #
      # @param type [Symbol] Singular metric type
      # @return [Symbol] Plural stats key
      def convert_type_to_plural(type)
        case type
        when :counter then :counters
        when :gauge then :gauges
        when :histogram then :histograms
        else type
        end
      end

      # Calculate exponential backoff delay
      #
      # @param retry_count [Integer] Current retry attempt
      # @return [Float] Delay in seconds
      def calculate_backoff_delay(retry_count)
        0.001 * retry_count
      end

      # Create versioned snapshot with enhanced metadata
      #
      # @return [Hash] Versioned snapshot data
      def create_versioned_snapshot
        {
          version: Tasker::VERSION,
          timestamp: Time.current.iso8601,
          instance_id: @instance_id,
          cache_strategy: @sync_strategy,
          cache_capabilities: @cache_capabilities,
          total_metrics: @metrics.size,
          metrics_by_type: @metrics.group_by { |_k, v| v.to_h[:type] }.transform_values(&:size),
          metrics: @metrics.transform_values(&:to_h),
          sync_config: @sync_config.slice(:retention_window, :batch_size),
          hostname: ENV['HOSTNAME'] || Socket.gethostname
        }
      end

      # Estimate snapshot size for monitoring
      #
      # @param snapshot_data [Hash] Snapshot data
      # @return [Integer] Estimated size in bytes
      def estimate_snapshot_size(snapshot_data)
        # Rough estimation based on JSON serialization
        snapshot_data.to_json.bytesize
      rescue StandardError
        0
      end

      # Check if Rails.cache is available and functional
      #
      # @return [Boolean] True if Rails.cache can be used
      def rails_cache_available?
        defined?(Rails) && Rails.cache.respond_to?(:read) && Rails.cache.respond_to?(:write)
      rescue StandardError
        false
      end

      # Default cache capabilities when detection fails
      #
      # Provides safe defaults aligned with Rails caching guide patterns
      #
      # @return [Hash] Safe default capabilities
      def default_cache_capabilities
        {
          distributed: false,
          atomic_increment: false,
          locking: false,
          ttl_inspection: false,
          store_class: 'Unknown',
          key_transformation: true, # Assume Rails key transformation
          namespace_support: false,
          compression_support: false
        }
      end

      # Log cache strategy selection for operational visibility
      def log_cache_strategy_selection
        return unless defined?(Rails) && Rails.logger

        Rails.logger.info "[Tasker::MetricsBackend] Cache strategy selected: #{@sync_strategy}"
        Rails.logger.info "[Tasker::MetricsBackend] Cache capabilities: #{@cache_capabilities}"
        Rails.logger.info "[Tasker::MetricsBackend] Instance ID: #{@instance_id}"
      end

      # Log detected cache capabilities with detailed breakdown
      #
      # @param capabilities [Hash] Detected capabilities
      def log_cache_capabilities_detected(capabilities)
        return unless defined?(Rails) && Rails.logger

        Rails.logger.debug { "[Tasker::MetricsBackend] Cache store detected: #{capabilities[:store_class]}" }
        Rails.logger.debug { "[Tasker::MetricsBackend] Distributed: #{capabilities[:distributed]}" }
        Rails.logger.debug { "[Tasker::MetricsBackend] Atomic operations: #{capabilities[:atomic_increment]}" }
        Rails.logger.debug { "[Tasker::MetricsBackend] Locking support: #{capabilities[:locking]}" }
        Rails.logger.debug { "[Tasker::MetricsBackend] Namespace support: #{capabilities[:namespace_support]}" }
      end

      # Log cache detection errors
      #
      # @param error [Exception] Detection error
      def log_cache_detection_error(error)
        return unless defined?(Rails) && Rails.logger

        Rails.logger.warn "[Tasker::MetricsBackend] Cache detection failed: #{error.message}"
        Rails.logger.warn '[Tasker::MetricsBackend] Falling back to local-only mode'
      end

      # Log sync errors
      #
      # @param error [Exception] Sync error
      def log_sync_error(error)
        return unless defined?(Rails) && Rails.logger

        Rails.logger.error "[Tasker::MetricsBackend] Cache sync failed: #{error.message}"
      end

      # Log local-only mode usage
      def log_local_only_mode
        return unless defined?(Rails) && Rails.logger

        Rails.logger.info "[Tasker::MetricsBackend] Cache store doesn't support distribution - using local-only mode"
      end

      # **Phase 4.2.2.3.2 Enhanced Logging Methods**
      # =============================================

      def log_atomic_sync_success(stats, duration)
        return unless defined?(Rails) && Rails.logger

        total_synced = stats.values_at(:counters, :gauges, :histograms).sum
        Rails.logger.info(
          '[Tasker::Telemetry] Atomic sync completed: ' \
          "#{total_synced} metrics (#{stats[:counters]}c/#{stats[:gauges]}g/#{stats[:histograms]}h) " \
          "in #{(duration * 1000).round(2)}ms, #{stats[:conflicts]} conflicts, #{stats[:batches]} batches"
        )
      end

      def log_rmw_sync_success(stats, duration)
        return unless defined?(Rails) && Rails.logger

        total_synced = stats.values_at(:counters, :gauges, :histograms).sum
        Rails.logger.info(
          '[Tasker::Telemetry] Read-modify-write sync completed: ' \
          "#{total_synced} metrics (#{stats[:counters]}c/#{stats[:gauges]}g/#{stats[:histograms]}h) " \
          "in #{(duration * 1000).round(2)}ms, #{stats[:retries]} retries, #{stats[:failed]} failed"
        )
      end

      def log_local_sync_success(stats, duration)
        return unless defined?(Rails) && Rails.logger

        Rails.logger.info(
          '[Tasker::Telemetry] Local snapshot sync completed: ' \
          "#{stats[:metrics_serialized]} metrics in #{stats[:snapshots]} snapshots " \
          "(#{stats[:size_bytes]} bytes) in #{(duration * 1000).round(2)}ms"
        )
      end

      # Coordinate cache sync with export system
      #
      # @param sync_result [Hash] Result from cache sync operation
      def coordinate_cache_sync(sync_result)
        return unless defined?(Tasker::Telemetry::ExportCoordinator)

        begin
          coordinator = Tasker::Telemetry::ExportCoordinator.instance
          coordinator.coordinate_cache_sync(sync_result)
        rescue StandardError => e
          # Don't fail sync operation due to coordination errors
          Rails.logger&.warn("Export coordination failed: #{e.message}")
        end
      end
    end
  end
end
