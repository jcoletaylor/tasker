# frozen_string_literal: true

require 'timeout'

module Tasker
  module Health
    # ReadinessChecker validates basic system readiness
    #
    # Performs lightweight checks to determine if the system can accept new requests.
    # Designed for Kubernetes readiness probes with fast response times.
    #
    # @example Basic usage
    #   checker = Tasker::Health::ReadinessChecker.new
    #   result = checker.check
    #   puts result[:ready]  # true/false
    #
    # @example With custom timeout
    #   checker = Tasker::Health::ReadinessChecker.new(timeout: 3.0)
    #   result = checker.check
    class ReadinessChecker
      # @return [Float] Timeout for readiness checks in seconds
      attr_reader :timeout

      # Initialize readiness checker
      #
      # @param timeout [Float] Maximum time to wait for checks (default: 5.0 seconds)
      def initialize(timeout: nil)
        @timeout = timeout || Tasker::Configuration.configuration.health.readiness_timeout_seconds
      end

      # Class method for simple readiness check
      #
      # @return [Boolean] Whether system is ready
      def self.ready?
        new.check[:ready]
      end

      # Class method for detailed readiness status
      #
      # @return [Hash] Detailed readiness status
      def self.detailed_status
        new.check
      end

      # Perform readiness check
      #
      # @return [Hash] Readiness status with details
      #   - :ready [Boolean] Overall readiness status
      #   - :checks [Hash] Individual check results
      #   - :message [String] Status message
      #   - :timestamp [Time] When check was performed
      def check
        start_time = Time.current
        checks = {}

        begin
          # Use timeout protection for all checks
          Timeout.timeout(@timeout) do
            checks[:database] = check_database_connection_with_timing
            checks[:cache] = check_cache_availability_with_timing
          end

          ready = checks.values.all? { |check| check[:status] == 'healthy' }
          failed_checks = checks.select { |_name, check| check[:status] == 'unhealthy' }.keys.map(&:to_s)

          result = {
            ready: ready,
            checks: checks,
            message: ready ? 'System is ready' : 'System is not ready',
            timestamp: Time.current,
            check_duration: Time.current - start_time
          }

          # Add failed_checks if there are any failures
          result[:failed_checks] = failed_checks unless failed_checks.empty?
          result
        rescue Timeout::Error
          {
            ready: false,
            checks: checks,
            message: "Readiness check timed out after #{@timeout} seconds",
            timestamp: Time.current,
            check_duration: Time.current - start_time
          }
        rescue StandardError => e
          {
            ready: false,
            checks: checks,
            message: "Readiness check failed: #{e.message}",
            error: e.class.name,
            timestamp: Time.current,
            check_duration: Time.current - start_time
          }
        end
      end

      private

      # Check database connection with timing
      #
      # @return [Hash] Database check result with response time
      def check_database_connection_with_timing
        start_time = Time.current
        ActiveRecord::Base.connection.execute('SELECT 1')
        response_time = ((Time.current - start_time) * 1000).round(2)

        {
          status: 'healthy',
          message: 'Database connection active',
          response_time_ms: response_time
        }
      rescue StandardError => e
        response_time = ((Time.current - start_time) * 1000).round(2)
        {
          status: 'unhealthy',
          message: "Database connection failed: #{e.message}",
          error: "#{e.class.name}: #{e.message}",
          response_time_ms: response_time
        }
      end

      # Check cache availability with timing and strategy awareness
      #
      # Enhanced with cache strategy detection to provide detailed capability information
      # @return [Hash] Cache check result with response time and strategy details
      def check_cache_availability_with_timing
        start_time = Time.current

        # Get cache strategy for enhanced diagnostics
        cache_strategy = Tasker::CacheStrategy.detect

        # Simple cache test - write and read a test key
        test_key = "tasker_readiness_check_#{SecureRandom.hex(8)}"
        test_value = Time.current.to_i

        Rails.cache.write(test_key, test_value, expires_in: 1.minute)
        cached_value = Rails.cache.read(test_key)
        Rails.cache.delete(test_key) # cleanup

        response_time = ((Time.current - start_time) * 1000).round(2)

        if cached_value == test_value
          {
            status: 'healthy',
            message: 'Cache is available',
            response_time_ms: response_time,
            cache_store: cache_strategy.store_class_name,
            coordination_strategy: cache_strategy.coordination_mode,
            distributed: cache_strategy.supports?(:distributed),
            atomic_operations: cache_strategy.supports?(:atomic_increment),
            locking_support: cache_strategy.supports?(:locking)
          }
        else
          {
            status: 'unhealthy',
            message: 'Cache read/write test failed',
            error: 'CacheTestFailed',
            response_time_ms: response_time,
            cache_store: cache_strategy.store_class_name,
            coordination_strategy: cache_strategy.coordination_mode
          }
        end
      rescue StandardError => e
        response_time = ((Time.current - start_time) * 1000).round(2)

        # Try to get cache strategy info even if test failed
        strategy_info = begin
          strategy = Tasker::CacheStrategy.detect
          {
            cache_store: strategy.store_class_name,
            coordination_strategy: strategy.coordination_mode
          }
        rescue StandardError
          { cache_store: 'Unknown', coordination_strategy: 'unknown' }
        end

        {
          status: 'unhealthy',
          message: "Cache check failed: #{e.message}",
          error: "#{e.class.name}: #{e.message}",
          response_time_ms: response_time
        }.merge(strategy_info)
      end
    end
  end
end
