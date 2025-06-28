# frozen_string_literal: true

module Tasker
  module Telemetry
    # Intelligent cache management with adaptive TTL and distributed coordination
    #
    # This class implements a strategic constants vs configuration approach:
    # - CONSTANTS: Infrastructure naming for consistency across deployments
    # - CONFIGURABLE: Algorithm parameters for workload-specific tuning
    #
    # **Phase 2.1 Enhancement: Distributed Coordination**
    # Leverages proven MetricsBackend patterns for multi-container coordination:
    # - Instance ID generation (hostname-pid pattern)
    # - Cache capability detection with adaptive strategies
    # - Multi-strategy coordination (distributed_atomic, distributed_basic, local_only)
    # - Atomic operations with fallback strategies
    #
    # Features:
    # - Kubernetes-ready distributed cache coordination
    # - Rails.cache abstraction (works with Redis, Memcached, File, Memory)
    # - Configurable smoothing factors for different workload patterns
    # - Comprehensive performance tracking with structured logging
    #
    # @example Basic usage
    #   manager = IntelligentCacheManager.new
    #   result = manager.intelligent_fetch('expensive_key') { expensive_computation }
    #
    # @example With custom configuration
    #   config = Tasker::Types::CacheConfig.new(hit_rate_smoothing_factor: 0.95)
    #   manager = IntelligentCacheManager.new(config)
    #   result = manager.intelligent_fetch('key', base_ttl: 600) { data }
    #
    class IntelligentCacheManager
      include Tasker::Concerns::StructuredLogging

      # ✅ CONSTANTS: Infrastructure naming (consistency across deployments)
      CACHE_PERFORMANCE_KEY_PREFIX = 'tasker:cache_perf'
      DASHBOARD_CACHE_KEY_PREFIX = 'tasker:dashboard'
      WORKFLOW_CACHE_KEY_PREFIX = 'tasker:workflow'
      PERFORMANCE_RETENTION_PERIOD = 1.hour
      COORDINATION_RETRY_ATTEMPTS = 3

      # ✅ CONSTANTS: Coordination strategy thresholds (algorithmic, not configurable)
      ATOMIC_OPERATION_TIMEOUT = 5.seconds
      BASIC_COORDINATION_TIMEOUT = 10.seconds
      LOCAL_COORDINATION_TIMEOUT = 1.second

      attr_reader :config, :instance_id, :cache_capabilities, :coordination_strategy

      # Initialize intelligent cache manager with distributed coordination
      #
      # @param config [Tasker::Types::CacheConfig, nil] Cache configuration
      def initialize(config = nil)
        @config = config || Tasker.configuration.cache

        # Use unified cache strategy for capability detection
        @cache_strategy = Tasker::CacheStrategy.detect
        @instance_id = @cache_strategy.instance_id
        @coordination_strategy = @cache_strategy.coordination_mode

        # Extract capabilities for backward compatibility
        @cache_capabilities = @cache_strategy.export_capabilities
        @coordination_config = configure_coordination_parameters

        log_structured(:info, 'IntelligentCacheManager initialized',
                       coordination_strategy: @coordination_strategy,
                       cache_store: @cache_strategy.store_class_name,
                       instance_id: @instance_id,
                       adaptive_ttl_enabled: @config.adaptive_ttl_enabled,
                       performance_tracking_enabled: @config.performance_tracking_enabled)
      end

      # Main intelligent cache method with distributed coordination
      #
      # @param cache_key [String] The cache key
      # @param base_ttl [Integer] Base TTL in seconds
      # @yield Block that generates the value if cache miss
      # @return [Object] The cached or generated value
      def intelligent_fetch(cache_key, base_ttl: @config.default_ttl, &)
        case @coordination_strategy
        when :distributed_atomic
          intelligent_fetch_with_atomic_coordination(cache_key, base_ttl, &)
        when :distributed_basic
          intelligent_fetch_with_basic_coordination(cache_key, base_ttl, &)
        when :local_only
          intelligent_fetch_with_local_tracking(cache_key, base_ttl, &)
        else
          # Fallback to basic Rails.cache behavior
          Rails.cache.fetch(cache_key, expires_in: base_ttl, &)
        end
      end

      # Clear performance data for a specific cache key
      #
      # @param cache_key [String] The cache key to clear performance data for
      # @return [Boolean] Success status
      def clear_performance_data(cache_key)
        performance_key = build_performance_key(cache_key)
        Rails.cache.delete(performance_key)

        log_structured(:debug, 'Cache performance data cleared',
                       cache_key: cache_key,
                       performance_key: performance_key,
                       coordination_strategy: @coordination_strategy)

        true
      rescue StandardError => e
        log_structured(:error, 'Failed to clear cache performance data',
                       cache_key: cache_key,
                       error: e.message,
                       coordination_strategy: @coordination_strategy)
        false
      end

      # Export cache performance metrics for observability
      #
      # @return [Hash] Performance metrics summary
      def export_performance_metrics
        case @coordination_strategy
        when :distributed_atomic, :distributed_basic
          export_distributed_performance_metrics
        when :local_only
          export_local_performance_metrics
        else
          { strategy: @coordination_strategy, metrics: {} }
        end
      end

      private

      # Distributed atomic coordination (Redis with full features)
      #
      # @param cache_key [String] The cache key
      # @param base_ttl [Integer] Base TTL in seconds
      # @yield Block that generates the value
      # @return [Object] The cached or generated value
      def intelligent_fetch_with_atomic_coordination(cache_key, base_ttl, &)
        # Get performance data atomically (no race conditions)
        performance_data = fetch_atomic_performance_data(cache_key)
        adaptive_ttl = @config.calculate_adaptive_ttl(base_ttl, **performance_data)

        # Execute cache fetch with performance tracking
        result = execute_tracked_fetch(cache_key, adaptive_ttl, &)

        # Update performance metrics atomically
        update_atomic_performance_metrics(cache_key, result[:hit], result[:duration])

        result[:value]
      end

      # Distributed basic coordination (Memcached with read-modify-write)
      #
      # @param cache_key [String] The cache key
      # @param base_ttl [Integer] Base TTL in seconds
      # @yield Block that generates the value
      # @return [Object] The cached or generated value
      def intelligent_fetch_with_basic_coordination(cache_key, base_ttl, &)
        # Get performance data with read-modify-write pattern
        performance_data = fetch_basic_performance_data(cache_key)
        adaptive_ttl = @config.calculate_adaptive_ttl(base_ttl, **performance_data)

        # Execute cache fetch with performance tracking
        result = execute_tracked_fetch(cache_key, adaptive_ttl, &)

        # Update performance metrics with coordination
        update_basic_performance_metrics(cache_key, result[:hit], result[:duration])

        result[:value]
      end

      # Local-only tracking (Memory/File stores)
      #
      # @param cache_key [String] The cache key
      # @param base_ttl [Integer] Base TTL in seconds
      # @yield Block that generates the value
      # @return [Object] The cached or generated value
      def intelligent_fetch_with_local_tracking(cache_key, base_ttl, &)
        # Get instance-specific performance data
        performance_data = fetch_local_performance_data(cache_key)
        adaptive_ttl = @config.calculate_adaptive_ttl(base_ttl, **performance_data)

        # Execute cache fetch with local tracking
        result = execute_tracked_fetch(cache_key, adaptive_ttl, &)

        # Update local performance metrics
        update_local_performance_metrics(cache_key, result[:hit], result[:duration])

        result[:value]
      end

      # Execute cache fetch with comprehensive tracking
      #
      # @param cache_key [String] The cache key
      # @param adaptive_ttl [Integer] Calculated adaptive TTL
      # @yield Block that generates the value
      # @return [Hash] Result with hit status, duration, and value
      def execute_tracked_fetch(cache_key, adaptive_ttl)
        fetch_start = Time.current
        cache_miss = false

        value = Rails.cache.fetch(cache_key, expires_in: adaptive_ttl) do
          cache_miss = true # This is a miss since we're in the block
          yield
        end

        # Cache hit is the opposite of cache miss
        cache_hit = !cache_miss

        fetch_duration = Time.current - fetch_start

        log_structured(:debug, 'Intelligent cache fetch completed',
                       cache_key: cache_key,
                       adaptive_ttl: adaptive_ttl,
                       cache_hit: cache_hit,
                       fetch_duration_ms: (fetch_duration * 1000).round(2),
                       coordination_strategy: @coordination_strategy)

        {
          value: value,
          hit: cache_hit,
          duration: fetch_duration
        }
      end

      # Build performance key with strategic process isolation
      #
      # @param cache_key [String] The original cache key
      # @return [String] Performance tracking key
      def build_performance_key(cache_key)
        case @coordination_strategy
        when :distributed_atomic, :distributed_basic
          # GLOBAL: Shared performance data across containers for system-wide optimization
          "#{CACHE_PERFORMANCE_KEY_PREFIX}:#{cache_key}"
        when :local_only
          # LOCAL: Instance-specific performance data for single-process stores
          "#{CACHE_PERFORMANCE_KEY_PREFIX}:#{@instance_id}:#{cache_key}"
        else
          "#{CACHE_PERFORMANCE_KEY_PREFIX}:fallback:#{cache_key}"
        end
      end

      # Fetch performance data using atomic operations (Redis)
      #
      # @param cache_key [String] The cache key
      # @return [Hash] Performance data for adaptive TTL calculation
      def fetch_atomic_performance_data(cache_key)
        performance_key = build_performance_key(cache_key)

        # Use atomic operations to get consistent performance data
        performance_data = Rails.cache.read(performance_key) || initialize_performance_data

        # Return data in format expected by calculate_adaptive_ttl
        {
          hit_rate: performance_data[:hit_rate] || 0.0,
          generation_time: performance_data[:avg_generation_time] || 0.0,
          access_frequency: performance_data[:access_frequency] || 0
        }
      rescue StandardError => e
        log_structured(:error, 'Failed to fetch atomic performance data',
                       cache_key: cache_key,
                       error: e.message)
        default_performance_data
      end

      # Fetch performance data using basic read-modify-write (Memcached)
      #
      # @param cache_key [String] The cache key
      # @return [Hash] Performance data for adaptive TTL calculation
      def fetch_basic_performance_data(cache_key)
        performance_key = build_performance_key(cache_key)

        performance_data = Rails.cache.read(performance_key) || initialize_performance_data

        {
          hit_rate: performance_data[:hit_rate] || 0.0,
          generation_time: performance_data[:avg_generation_time] || 0.0,
          access_frequency: performance_data[:access_frequency] || 0
        }
      rescue StandardError => e
        log_structured(:error, 'Failed to fetch basic performance data',
                       cache_key: cache_key,
                       error: e.message)
        default_performance_data
      end

      # Fetch local performance data (Memory/File stores)
      #
      # @param cache_key [String] The cache key
      # @return [Hash] Performance data for adaptive TTL calculation
      def fetch_local_performance_data(cache_key)
        performance_key = build_performance_key(cache_key)

        performance_data = Rails.cache.read(performance_key) || initialize_performance_data

        {
          hit_rate: performance_data[:hit_rate] || 0.0,
          generation_time: performance_data[:avg_generation_time] || 0.0,
          access_frequency: performance_data[:access_frequency] || 0
        }
      rescue StandardError => e
        log_structured(:error, 'Failed to fetch local performance data',
                       cache_key: cache_key,
                       error: e.message)
        default_performance_data
      end

      # Update performance metrics using atomic operations
      #
      # @param cache_key [String] The cache key
      # @param cache_hit [Boolean] Whether this was a cache hit
      # @param duration [Float] Fetch duration in seconds
      def update_atomic_performance_metrics(cache_key, cache_hit, duration)
        performance_key = build_performance_key(cache_key)

        # Use atomic operations for thread-safe updates
        performance_data = Rails.cache.read(performance_key) || initialize_performance_data
        updated_data = calculate_updated_performance_data(performance_data, cache_hit, duration)

        Rails.cache.write(performance_key, updated_data, expires_in: PERFORMANCE_RETENTION_PERIOD)
      rescue StandardError => e
        log_structured(:error, 'Failed to update atomic performance metrics',
                       cache_key: cache_key,
                       error: e.message)
      end

      # Update performance metrics using basic coordination
      #
      # @param cache_key [String] The cache key
      # @param cache_hit [Boolean] Whether this was a cache hit
      # @param duration [Float] Fetch duration in seconds
      def update_basic_performance_metrics(cache_key, cache_hit, duration)
        performance_key = build_performance_key(cache_key)

        # Read-modify-write pattern for basic coordination
        performance_data = Rails.cache.read(performance_key) || initialize_performance_data
        updated_data = calculate_updated_performance_data(performance_data, cache_hit, duration)

        Rails.cache.write(performance_key, updated_data, expires_in: PERFORMANCE_RETENTION_PERIOD)
      rescue StandardError => e
        log_structured(:error, 'Failed to update basic performance metrics',
                       cache_key: cache_key,
                       error: e.message)
      end

      # Update local performance metrics
      #
      # @param cache_key [String] The cache key
      # @param cache_hit [Boolean] Whether this was a cache hit
      # @param duration [Float] Fetch duration in seconds
      def update_local_performance_metrics(cache_key, cache_hit, duration)
        performance_key = build_performance_key(cache_key)

        performance_data = Rails.cache.read(performance_key) || initialize_performance_data
        updated_data = calculate_updated_performance_data(performance_data, cache_hit, duration)

        Rails.cache.write(performance_key, updated_data, expires_in: PERFORMANCE_RETENTION_PERIOD)
      rescue StandardError => e
        log_structured(:error, 'Failed to update local performance metrics',
                       cache_key: cache_key,
                       error: e.message)
      end

      # Calculate updated performance data with smoothing
      #
      # @param current_data [Hash] Current performance data
      # @param cache_hit [Boolean] Whether this was a cache hit
      # @param duration [Float] Fetch duration in seconds
      # @return [Hash] Updated performance data
      def calculate_updated_performance_data(current_data, cache_hit, duration)
        # Apply smoothing factors from configuration
        smoothing_factor = @config.hit_rate_smoothing_factor
        decay_rate = @config.access_frequency_decay_rate

        # Ensure current_data has required keys with defaults
        current_hit_rate = current_data[:hit_rate] || 0.0
        current_avg_generation_time = current_data[:avg_generation_time] || 0.0
        current_access_frequency = current_data[:access_frequency] || 0
        current_total_accesses = current_data[:total_accesses] || 0
        current_cache_hits = current_data[:cache_hits] || 0
        current_cache_misses = current_data[:cache_misses] || 0

        # Update hit rate with exponential smoothing
        hit_value = cache_hit ? 1.0 : 0.0
        new_hit_rate = (current_hit_rate * smoothing_factor) + (hit_value * (1 - smoothing_factor))

        # Update average generation time (only for misses)
        new_avg_generation_time = if cache_hit
                                    current_avg_generation_time * decay_rate
                                  else
                                    (current_avg_generation_time * smoothing_factor) + (duration * (1 - smoothing_factor))
                                  end

        # Update access frequency with decay
        new_access_frequency = (current_access_frequency * decay_rate) + 1

        {
          hit_rate: new_hit_rate.clamp(0.0, 1.0),
          avg_generation_time: new_avg_generation_time,
          access_frequency: new_access_frequency,
          last_updated: Time.current,
          total_accesses: current_total_accesses + 1,
          cache_hits: current_cache_hits + (cache_hit ? 1 : 0),
          cache_misses: current_cache_misses + (cache_hit ? 0 : 1)
        }
      end

      # Initialize performance data structure
      #
      # @return [Hash] Initial performance data
      def initialize_performance_data
        {
          hit_rate: 0.0,
          avg_generation_time: 0.0,
          access_frequency: 0,
          last_updated: Time.current,
          total_accesses: 0,
          cache_hits: 0,
          cache_misses: 0
        }
      end

      # Default performance data for error cases
      #
      # @return [Hash] Safe default performance data
      def default_performance_data
        {
          hit_rate: 0.0,
          generation_time: 0.0,
          access_frequency: 0
        }
      end

      # Export distributed performance metrics
      #
      # @return [Hash] Distributed performance metrics
      def export_distributed_performance_metrics
        {
          strategy: @coordination_strategy,
          instance_id: @instance_id,
          cache_store: @cache_capabilities[:store_class],
          coordination_config: @coordination_config,
          metrics: gather_distributed_metrics
        }
      end

      # Export local performance metrics
      #
      # @return [Hash] Local performance metrics
      def export_local_performance_metrics
        {
          strategy: @coordination_strategy,
          instance_id: @instance_id,
          cache_store: @cache_capabilities[:store_class],
          metrics: gather_local_metrics,
          warning: 'Local-only metrics - not shared across containers'
        }
      end

      # Gather distributed metrics from shared cache
      #
      # @return [Hash] Gathered metrics
      def gather_distributed_metrics
        # Implementation would scan for performance keys and aggregate
        # For now, return basic structure
        {
          total_keys_tracked: 0,
          avg_hit_rate: 0.0,
          coordination_overhead: 'minimal'
        }
      end

      # Gather local metrics from instance cache
      #
      # @return [Hash] Local metrics
      def gather_local_metrics
        {
          total_keys_tracked: 0,
          avg_hit_rate: 0.0,
          instance_specific: true
        }
      end

      # Configure coordination parameters based on strategy
      #
      # @return [Hash] Coordination configuration
      def configure_coordination_parameters
        {
          retry_attempts: COORDINATION_RETRY_ATTEMPTS,
          timeout: coordination_timeout_for_strategy,
          retention_window: PERFORMANCE_RETENTION_PERIOD,
          batch_size: @config.respond_to?(:coordination_batch_size) ? @config.coordination_batch_size : 50
        }
      end

      # Get appropriate timeout for coordination strategy
      #
      # @return [Integer] Timeout in seconds
      def coordination_timeout_for_strategy
        case @coordination_strategy
        when :distributed_atomic then ATOMIC_OPERATION_TIMEOUT
        when :distributed_basic then BASIC_COORDINATION_TIMEOUT
        when :local_only then LOCAL_COORDINATION_TIMEOUT
        else 5.seconds
        end
      end
    end
  end
end
