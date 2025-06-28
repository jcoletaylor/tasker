# frozen_string_literal: true

module Tasker
  module Types
    # Configuration type for step execution and concurrency settings
    #
    # This configuration exposes previously hardcoded execution constants
    # used in concurrent step processing, timeout handling, and memory management.
    #
    # Strategic Design:
    # - CONFIGURABLE: Performance characteristics that vary by deployment environment
    # - ARCHITECTURAL: Carefully chosen constants based on Ruby/Rails characteristics
    #
    # @example Basic usage
    #   config = ExecutionConfig.new(
    #     max_concurrent_steps_limit: 20,  # High-performance system
    #     batch_timeout_base_seconds: 60   # API-heavy workflows
    #   )
    #
    # @example Environment-specific tuning
    #   # Development environment
    #   config = ExecutionConfig.new(
    #     min_concurrent_steps: 2,
    #     max_concurrent_steps_limit: 6,
    #     concurrency_cache_duration: 60
    #   )
    #
    #   # Production environment
    #   config = ExecutionConfig.new(
    #     min_concurrent_steps: 5,
    #     max_concurrent_steps_limit: 25,
    #     batch_timeout_base_seconds: 45,
    #     max_batch_timeout_seconds: 300
    #   )
    class ExecutionConfig < BaseConfig
      transform_keys(&:to_sym)

      # ====================
      # CONFIGURABLE SETTINGS
      # ====================
      # These affect performance characteristics and should vary by deployment

      # Minimum concurrent steps allowed
      #
      # Conservative bound to ensure system stability even under extreme load.
      # Small systems might prefer 2, large systems might prefer 5+.
      #
      # @!attribute [r] min_concurrent_steps
      #   @return [Integer] Minimum concurrent steps (default: 3)
      attribute :min_concurrent_steps, Types::Integer.default(3)

      # Maximum concurrent steps limit
      #
      # Upper bound for dynamic concurrency calculation.
      # High-performance systems with large connection pools can handle 20-30+.
      # Standard deployments typically use 8-15.
      #
      # @!attribute [r] max_concurrent_steps_limit
      #   @return [Integer] Maximum concurrent steps limit (default: 12)
      attribute :max_concurrent_steps_limit, Types::Integer.default(12)

      # Cache duration for concurrency calculation
      #
      # How long to cache the calculated optimal concurrency before recalculating.
      # Busy systems might want shorter cache (15s), stable systems longer (60s).
      #
      # @!attribute [r] concurrency_cache_duration
      #   @return [Integer] Cache duration in seconds (default: 30)
      attribute :concurrency_cache_duration, Types::Integer.default(30)

      # Base timeout for batch execution
      #
      # Starting timeout before per-step adjustments.
      # API-heavy workflows might need 60s+, simple workflows can use 15-20s.
      #
      # @!attribute [r] batch_timeout_base_seconds
      #   @return [Integer] Base timeout in seconds (default: 30)
      attribute :batch_timeout_base_seconds, Types::Integer.default(30)

      # Per-step timeout addition
      #
      # Additional timeout per step in a batch.
      # Complex steps might need 10s+, simple steps can use 2-3s.
      #
      # @!attribute [r] batch_timeout_per_step_seconds
      #   @return [Integer] Per-step timeout in seconds (default: 5)
      attribute :batch_timeout_per_step_seconds, Types::Integer.default(5)

      # Maximum batch timeout ceiling
      #
      # Absolute maximum timeout regardless of batch size.
      # Long-running workflows might need 300-600s, fast workflows 60-120s.
      #
      # @!attribute [r] max_batch_timeout_seconds
      #   @return [Integer] Maximum timeout in seconds (default: 120)
      attribute :max_batch_timeout_seconds, Types::Integer.default(120)

      # ====================
      # ARCHITECTURAL CONSTANTS
      # ====================
      # These are carefully chosen based on Ruby/Rails characteristics
      # and should NOT be exposed as configuration options

      # Future cleanup wait time
      #
      # Time to wait for executing futures during cleanup.
      # Based on Ruby Concurrent::Future characteristics - 1 second is optimal
      # for most Ruby applications and provides good balance of responsiveness
      # vs resource cleanup.
      #
      # @return [Integer] Wait time in seconds
      def future_cleanup_wait_seconds
        1
      end

      # GC trigger batch size threshold
      #
      # Batch size that triggers intelligent garbage collection.
      # Based on Ruby memory management patterns - 6 concurrent operations
      # is typically where memory pressure becomes noticeable in Ruby.
      #
      # @return [Integer] Batch size threshold
      def gc_trigger_batch_size_threshold
        6
      end

      # GC trigger duration threshold
      #
      # Batch duration that triggers intelligent garbage collection.
      # Based on Ruby GC timing characteristics - 30 seconds is typically
      # when Ruby benefits from explicit GC triggering.
      #
      # @return [Integer] Duration threshold in seconds
      def gc_trigger_duration_threshold
        30
      end

      # ====================
      # CALCULATED VALUES
      # ====================

      # Calculate batch timeout for a given batch size
      #
      # @param batch_size [Integer] Number of steps in the batch
      # @return [Integer] Calculated timeout in seconds
      def calculate_batch_timeout(batch_size)
        calculated_timeout = batch_timeout_base_seconds + (batch_size * batch_timeout_per_step_seconds)
        [calculated_timeout, max_batch_timeout_seconds].min
      end

      # Check if batch should trigger garbage collection
      #
      # @param batch_size [Integer] Size of the batch
      # @param batch_duration [Float] Duration of batch execution in seconds
      # @return [Boolean] Whether to trigger GC
      def should_trigger_gc?(batch_size, batch_duration)
        batch_size >= gc_trigger_batch_size_threshold ||
          batch_duration >= gc_trigger_duration_threshold
      end

      # Validate concurrency bounds
      #
      # Ensures min <= max and both are positive
      # @return [Array<String>] Validation errors (empty if valid)
      def validate_concurrency_bounds
        errors = []

        errors << "min_concurrent_steps must be positive (got: #{min_concurrent_steps})" if min_concurrent_steps <= 0

        if max_concurrent_steps_limit <= 0
          errors << "max_concurrent_steps_limit must be positive (got: #{max_concurrent_steps_limit})"
        end

        if min_concurrent_steps > max_concurrent_steps_limit
          errors << "min_concurrent_steps (#{min_concurrent_steps}) cannot exceed max_concurrent_steps_limit (#{max_concurrent_steps_limit})"
        end

        errors
      end

      # Validate timeout configuration
      #
      # Ensures timeouts are positive and logical
      # @return [Array<String>] Validation errors (empty if valid)
      def validate_timeout_configuration
        errors = []

        if batch_timeout_base_seconds <= 0
          errors << "batch_timeout_base_seconds must be positive (got: #{batch_timeout_base_seconds})"
        end

        if batch_timeout_per_step_seconds <= 0
          errors << "batch_timeout_per_step_seconds must be positive (got: #{batch_timeout_per_step_seconds})"
        end

        if max_batch_timeout_seconds <= batch_timeout_base_seconds
          errors << "max_batch_timeout_seconds (#{max_batch_timeout_seconds}) must be greater than batch_timeout_base_seconds (#{batch_timeout_base_seconds})"
        end

        errors
      end

      # Comprehensive validation
      #
      # @return [Array<String>] All validation errors (empty if valid)
      def validate!
        errors = validate_concurrency_bounds + validate_timeout_configuration

        raise Dry::Struct::Error, "ExecutionConfig validation failed: #{errors.join(', ')}" unless errors.empty?

        true
      end
    end
  end
end
