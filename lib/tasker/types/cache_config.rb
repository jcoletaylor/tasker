# frozen_string_literal: true

module Tasker
  module Types
    # Configuration type for intelligent cache strategy settings
    #
    # This configuration provides strategic control over cache behavior while
    # maintaining consistent infrastructure naming through constants.
    #
    # Strategic Design:
    # - CONFIGURABLE: Algorithm parameters that vary by workload characteristics
    # - CONFIGURABLE: Performance thresholds that vary by deployment environment
    # - CONSTANTS: Infrastructure naming for consistency across deployments
    #
    # @example Basic usage
    #   config = CacheConfig.new(
    #     default_ttl: 600,                    # 10 minutes for stable data
    #     hit_rate_smoothing_factor: 0.8       # Less aggressive smoothing
    #   )
    #
    # @example Environment-specific tuning
    #   # Development environment - shorter TTLs for rapid iteration
    #   config = CacheConfig.new(
    #     default_ttl: 120,                    # 2 minutes
    #     adaptive_ttl_enabled: false,         # Disable complexity
    #     performance_tracking_enabled: false  # Reduce overhead
    #   )
    #
    #   # Production environment - optimized for performance
    #   config = CacheConfig.new(
    #     default_ttl: 300,                    # 5 minutes
    #     hit_rate_smoothing_factor: 0.95,     # Aggressive smoothing
    #     access_frequency_decay_rate: 0.98,   # Slow decay
    #     adaptive_ttl_enabled: true,          # Enable intelligence
    #     performance_tracking_enabled: true   # Full observability
    #   )
    #
    #   # High-performance environment - maximum efficiency
    #   config = CacheConfig.new(
    #     default_ttl: 600,                    # 10 minutes
    #     min_adaptive_ttl: 60,                # 1 minute minimum
    #     max_adaptive_ttl: 7200,              # 2 hours maximum
    #     cache_pressure_threshold: 0.9,       # High threshold
    #     adaptive_calculation_interval: 15    # Frequent recalculation
    #   )
    class CacheConfig < BaseConfig
      transform_keys(&:to_sym)

      # ====================
      # CONFIGURABLE SETTINGS
      # ====================
      # These affect performance characteristics and should vary by deployment

      # Default cache TTL in seconds
      #
      # Base time-to-live for cache entries before adaptive calculation.
      # Fast-changing data might need 60-120s, stable data can use 300-600s.
      #
      # @!attribute [r] default_ttl
      #   @return [Integer] Default TTL in seconds (default: 300)
      attribute :default_ttl, Types::Integer.default(300)

      # Enable adaptive TTL calculation
      #
      # Whether to use intelligent TTL adjustment based on hit rates and generation time.
      # Development environments might disable this for simplicity.
      #
      # @!attribute [r] adaptive_ttl_enabled
      #   @return [Boolean] Whether adaptive TTL is enabled (default: true)
      attribute :adaptive_ttl_enabled, Types::Bool.default(true)

      # Enable performance tracking
      #
      # Whether to track cache performance metrics for adaptive calculation.
      # Adds small overhead but enables intelligent optimization.
      #
      # @!attribute [r] performance_tracking_enabled
      #   @return [Boolean] Whether performance tracking is enabled (default: true)
      attribute :performance_tracking_enabled, Types::Bool.default(true)

      # Hit rate smoothing factor for exponential moving average
      #
      # Controls how quickly hit rate adapts to new data.
      # Higher values (0.95+) = slower adaptation, more stable
      # Lower values (0.8-) = faster adaptation, more responsive
      #
      # @!attribute [r] hit_rate_smoothing_factor
      #   @return [Float] Smoothing factor (default: 0.9)
      attribute :hit_rate_smoothing_factor, Types::Float.default(0.9)

      # Access frequency decay rate for daily patterns
      #
      # Controls how access frequency decays over time.
      # Higher values (0.98+) = slow decay, long memory
      # Lower values (0.9-) = fast decay, short memory
      #
      # @!attribute [r] access_frequency_decay_rate
      #   @return [Float] Decay rate (default: 0.95)
      attribute :access_frequency_decay_rate, Types::Float.default(0.95)

      # Minimum adaptive TTL bound
      #
      # Absolute minimum TTL regardless of adaptive calculation.
      # Prevents thrashing with very short cache times.
      #
      # @!attribute [r] min_adaptive_ttl
      #   @return [Integer] Minimum TTL in seconds (default: 30)
      attribute :min_adaptive_ttl, Types::Integer.default(30)

      # Maximum adaptive TTL bound
      #
      # Absolute maximum TTL regardless of adaptive calculation.
      # Prevents stale data with very long cache times.
      #
      # @!attribute [r] max_adaptive_ttl
      #   @return [Integer] Maximum TTL in seconds (default: 3600)
      attribute :max_adaptive_ttl, Types::Integer.default(3600)

      # Dashboard cache TTL
      #
      # Specific TTL for dashboard and analytics queries.
      # Should be shorter than default for responsive dashboards.
      #
      # @!attribute [r] dashboard_cache_ttl
      #   @return [Integer] Dashboard TTL in seconds (default: 120)
      attribute :dashboard_cache_ttl, Types::Integer.default(120)

      # Cache pressure threshold
      #
      # Utilization threshold that triggers cache pressure responses.
      # Higher values = more aggressive caching, lower = more conservative.
      #
      # @!attribute [r] cache_pressure_threshold
      #   @return [Float] Pressure threshold (default: 0.8)
      attribute :cache_pressure_threshold, Types::Float.default(0.8)

      # Adaptive calculation interval
      #
      # How often to recalculate adaptive TTL values in seconds.
      # Shorter intervals = more responsive, longer = more stable.
      #
      # @!attribute [r] adaptive_calculation_interval
      #   @return [Integer] Calculation interval in seconds (default: 30)
      attribute :adaptive_calculation_interval, Types::Integer.default(30)

      # ====================
      # VALIDATION METHODS
      # ====================

      # Validate TTL configuration
      #
      # Ensures TTL values are positive and logical
      # @return [Array<String>] Validation errors (empty if valid)
      def validate_ttl_configuration
        errors = []

        errors << "default_ttl must be positive (got: #{default_ttl})" if default_ttl <= 0

        errors << "min_adaptive_ttl must be positive (got: #{min_adaptive_ttl})" if min_adaptive_ttl <= 0

        errors << "max_adaptive_ttl must be positive (got: #{max_adaptive_ttl})" if max_adaptive_ttl <= 0

        if min_adaptive_ttl >= max_adaptive_ttl
          errors << "min_adaptive_ttl (#{min_adaptive_ttl}) must be less than max_adaptive_ttl (#{max_adaptive_ttl})"
        end

        errors << "dashboard_cache_ttl must be positive (got: #{dashboard_cache_ttl})" if dashboard_cache_ttl <= 0

        errors
      end

      # Validate algorithm parameters
      #
      # Ensures smoothing factors and thresholds are within valid ranges
      # @return [Array<String>] Validation errors (empty if valid)
      def validate_algorithm_parameters
        errors = []

        unless (0.0..1.0).cover?(hit_rate_smoothing_factor)
          errors << "hit_rate_smoothing_factor must be between 0.0 and 1.0 (got: #{hit_rate_smoothing_factor})"
        end

        unless (0.0..1.0).cover?(access_frequency_decay_rate)
          errors << "access_frequency_decay_rate must be between 0.0 and 1.0 (got: #{access_frequency_decay_rate})"
        end

        unless (0.0..1.0).cover?(cache_pressure_threshold)
          errors << "cache_pressure_threshold must be between 0.0 and 1.0 (got: #{cache_pressure_threshold})"
        end

        if adaptive_calculation_interval <= 0
          errors << "adaptive_calculation_interval must be positive (got: #{adaptive_calculation_interval})"
        end

        errors
      end

      # Validate entire configuration
      #
      # Runs all validation checks and raises if any errors found
      # @raise [ArgumentError] If configuration is invalid
      def validate!
        errors = validate_ttl_configuration + validate_algorithm_parameters

        return if errors.empty?

        raise ArgumentError, "Invalid cache configuration: #{errors.join(', ')}"
      end

      # Calculate adaptive TTL based on performance data
      #
      # @param base_ttl [Integer] Base TTL to adjust
      # @param hit_rate [Float] Current cache hit rate (0.0-1.0)
      # @param generation_time [Float] Average generation time in seconds
      # @param access_frequency [Integer] Access frequency count
      # @return [Integer] Calculated adaptive TTL
      def calculate_adaptive_ttl(base_ttl, hit_rate: 0.0, generation_time: 0.0, access_frequency: 0)
        return base_ttl unless adaptive_ttl_enabled

        # Start with base TTL as float for more precise calculations
        adaptive_ttl = base_ttl.to_f

        # Adjust based on hit rate (only if we have meaningful data)
        if hit_rate > 0.8
          adaptive_ttl *= 1.5  # High hit rate, extend TTL
        elsif hit_rate > 0.0 && hit_rate < 0.3
          adaptive_ttl *= 0.7  # Low hit rate, reduce TTL
        end

        # Adjust based on generation time (only if we have meaningful data)
        if generation_time > 1.0
          adaptive_ttl *= 1.3  # Expensive to generate, cache longer
        elsif generation_time > 0.0 && generation_time < 0.1
          adaptive_ttl *= 0.8  # Cheap to generate, cache shorter
        end

        # Adjust based on access frequency (only if we have meaningful data)
        if access_frequency > 100
          adaptive_ttl *= 1.2  # Frequently accessed, cache longer
        elsif access_frequency.positive? && access_frequency < 5
          adaptive_ttl *= 0.9  # Rarely accessed, cache shorter
        end

        # Convert to integer and apply bounds
        adaptive_ttl.to_i.clamp(min_adaptive_ttl, max_adaptive_ttl)
      end

      # Check if cache is under pressure
      #
      # @param utilization [Float] Current cache utilization (0.0-1.0)
      # @return [Boolean] Whether cache is under pressure
      def cache_under_pressure?(utilization)
        utilization >= cache_pressure_threshold
      end
    end
  end
end
