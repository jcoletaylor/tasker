# frozen_string_literal: true

module Tasker
  module Health
    # StatusChecker provides comprehensive system status information
    #
    # Gathers detailed metrics about tasks, workflow steps, and system health.
    # Uses Rails caching to avoid expensive database queries on frequent requests.
    #
    # @example Basic usage
    #   checker = Tasker::Health::StatusChecker.new
    #   status = checker.check
    #   puts status[:healthy]
    #
    # @example Force refresh (bypass cache)
    #   status = checker.check(force_refresh: true)
    class StatusChecker
      # @return [Integer] Cache duration in seconds
      attr_reader :cache_duration

      # Cache key for status data
      CACHE_KEY = 'tasker:health:status'

      # Initialize status checker
      #
      # @param cache_duration [Integer] Cache duration in seconds (default from config)
      def initialize(cache_duration: nil)
        @cache_duration = cache_duration || Tasker.configuration.health.cache_duration_seconds
      end

      # Class method for status check
      #
      # @return [Hash] Comprehensive status information
      def self.status
        new.check
      end

      # Perform comprehensive status check
      #
      # @param force_refresh [Boolean] Whether to bypass cache and force fresh data
      # @return [Hash] Comprehensive status information
      #   - :healthy [Boolean] Overall system health
      #   - :status [String] Status description
      #   - :data [Hash] Detailed metrics
      #   - :cached [Boolean] Whether data came from cache
      #   - :timestamp [Time] When data was generated
      def check(force_refresh: false)
        if force_refresh
          result = generate_status_data
          result[:cached] = false
          result
        else
          begin
            # Check if we have cached data first
            cached_data = Rails.cache.read(CACHE_KEY)
            if cached_data.nil?
              # No cached data, generate fresh and cache it
              result = generate_status_data
              # Create a copy for caching (without the cached flag)
              cache_data = result.dup
              cache_data.delete(:cached)
              Rails.cache.write(CACHE_KEY, cache_data, expires_in: @cache_duration.seconds)
              result[:cached] = false
            else
              # Return cached data with cached flag set
              result = cached_data.dup
              result[:cached] = true
            end
            result
          rescue StandardError => e
            # If cache fails, generate fresh data
            result = generate_status_data
            result[:cached] = false
            result[:cache_error] = "Cache error: #{e.message}"
            result
          end
        end
      end

      private

      # Generate fresh status data
      #
      # @return [Hash] Fresh status information
      def generate_status_data
        start_time = Time.current

        begin
          # Get health metrics from SQL function
          health_data = Tasker::Functions::FunctionBasedSystemHealthCounts.call

          # Determine overall health status
          healthy = assess_system_health(health_data)

          formatted_data = format_health_data(health_data)

          {
            healthy: healthy,
            status: healthy ? 'healthy' : 'unhealthy',
            metrics: formatted_data[:metrics],
            database: formatted_data[:database],
            cached: false,
            timestamp: start_time,
            generation_duration: Time.current - start_time
          }
        rescue StandardError => e
          {
            healthy: false,
            status: 'error',
            error: e.message,
            error_class: e.class.name,
            cached: false,
            timestamp: start_time,
            generation_duration: Time.current - start_time
          }
        end
      end

      # Assess overall system health based on metrics
      #
      # @param health_data [FunctionBasedSystemHealthCounts::HealthMetrics] Health metrics from SQL function
      # @return [Boolean] Whether system is healthy
      def assess_system_health(health_data)
        # System is healthy if:
        # 1. Database is responding (we got data)
        # 2. Connection utilization is reasonable (< 90%)
        # 3. No excessive error accumulation (< 50% error rate)

        return false if health_data.nil?

        # Check database connection utilization
        if health_data.max_connections.positive?
          connection_utilization = (health_data.active_connections.to_f / health_data.max_connections) * 100
          return false if connection_utilization > 90.0
        end

        # Check task error rate (only if we have tasks)
        if health_data.total_tasks.positive?
          task_error_rate = (health_data.error_tasks.to_f / health_data.total_tasks) * 100
          return false if task_error_rate > 50.0
        end

        # Check step error rate (only if we have steps)
        if health_data.total_steps.positive?
          step_error_rate = (health_data.error_steps.to_f / health_data.total_steps) * 100
          return false if step_error_rate > 50.0
        end

        true
      end

      # Format health data for API response
      #
      # @param health_data [FunctionBasedSystemHealthCounts::HealthMetrics] Raw health metrics
      # @return [Hash] Formatted health data with :metrics and :database keys
      def format_health_data(health_data)
        {
          metrics: {
            tasks: {
              total: health_data.total_tasks,
              pending: health_data.pending_tasks,
              in_progress: health_data.in_progress_tasks,
              complete: health_data.complete_tasks,
              error: health_data.error_tasks,
              cancelled: health_data.cancelled_tasks
            },
            steps: {
              total: health_data.total_steps,
              pending: health_data.pending_steps,
              in_progress: health_data.in_progress_steps,
              complete: health_data.complete_steps,
              error: health_data.error_steps
            },
            retries: {
              retryable_errors: health_data.retryable_error_steps,
              exhausted_retries: health_data.exhausted_retry_steps,
              in_backoff: health_data.in_backoff_steps
            }
          },
          database: {
            active_connections: health_data.active_connections,
            max_connections: health_data.max_connections,
            connection_utilization: calculate_utilization_percentage(
              health_data.active_connections,
              health_data.max_connections
            ) # Return as percentage (e.g., 5.0 for 5%)
          }
        }
      end

      # Calculate connection utilization percentage
      #
      # @param active [Integer] Active connections
      # @param max [Integer] Maximum connections
      # @return [Float] Utilization percentage
      def calculate_utilization_percentage(active, max)
        return 0.0 if max.zero?

        ((active.to_f / max) * 100).round(2)
      end
    end
  end
end
