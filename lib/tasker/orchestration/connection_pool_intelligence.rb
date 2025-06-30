# frozen_string_literal: true

module Tasker
  module Orchestration
    # Rails-Framework-Aligned Connection Management
    #
    # Provides intelligent assessment of database connection pool health and
    # recommends safe concurrency levels that work WITH Rails connection pool
    # rather than around it.
    #
    # Key Design Principles:
    # - CONSTANTS: Ruby/Rails optimization characteristics (safety thresholds, precision)
    # - CONFIGURABLE: Environment-dependent pressure response factors
    # - Conservative safety margins to prevent connection exhaustion
    # - Comprehensive structured logging for observability
    #
    # @example Basic usage
    #   health = ConnectionPoolIntelligence.assess_connection_health
    #   concurrency = ConnectionPoolIntelligence.intelligent_concurrency_for_step_executor
    #
    # @example With custom configuration
    #   config = Tasker.configuration.execution
    #   config.connection_pressure_factors = { high: 0.3, critical: 0.1 }
    #   concurrency = ConnectionPoolIntelligence.intelligent_concurrency_for_step_executor
    class ConnectionPoolIntelligence
      # ✅ CONSTANTS: Ruby/Rails optimization characteristics
      # These are based on Rails connection pool behavior and should NOT be configurable

      # Decimal places for utilization calculation (based on Rails pool stat precision)
      CONNECTION_UTILIZATION_PRECISION = 3

      # Pressure assessment thresholds (based on Rails connection pool characteristics)
      PRESSURE_ASSESSMENT_THRESHOLDS = {
        low: 0.0..0.5,
        moderate: 0.5..0.7,
        high: 0.7..0.85,
        critical: 0.85..Float::INFINITY
      }.freeze

      # Conservative safety patterns (based on Rails connection pool behavior)
      # Never use more than 60% of pool to prevent connection exhaustion
      MAX_SAFE_CONNECTION_PERCENTAGE = 0.6

      # Absolute minimum for system stability (based on Tasker orchestration needs)
      EMERGENCY_FALLBACK_CONCURRENCY = 3

      # Assess current database connection pool health
      #
      # Provides comprehensive analysis of Rails connection pool state including
      # utilization metrics, pressure assessment, and concurrency recommendations.
      #
      # @return [Hash] Connection health assessment with structured metrics
      #   @option return [Float] :pool_utilization Connection pool utilization ratio (0.0-1.0+)
      #   @option return [Symbol] :connection_pressure Pressure level (:low, :moderate, :high, :critical)
      #   @option return [Integer] :recommended_concurrency Safe concurrency level
      #   @option return [Hash] :rails_pool_stats Raw Rails pool statistics
      #   @option return [Symbol] :health_status Overall health status
      #   @option return [Time] :assessment_timestamp When assessment was performed
      def self.assess_connection_health
        pool = ActiveRecord::Base.connection_pool
        pool_stat = pool.stat

        {
          pool_utilization: calculate_utilization(pool_stat),
          connection_pressure: assess_pressure(pool_stat),
          recommended_concurrency: recommend_concurrency(pool_stat),
          rails_pool_stats: pool_stat,
          health_status: determine_health_status(pool_stat),
          assessment_timestamp: Time.current
        }
      rescue StandardError => e
        Rails.logger.error("ConnectionPoolIntelligence: Health assessment failed - #{e.class.name}: #{e.message}")

        # Return safe fallback assessment
        {
          pool_utilization: 0.0,
          connection_pressure: :unknown,
          recommended_concurrency: EMERGENCY_FALLBACK_CONCURRENCY,
          rails_pool_stats: {},
          health_status: :unknown,
          assessment_timestamp: Time.current,
          assessment_error: e.message
        }
      end

      # Calculate intelligent concurrency for StepExecutor integration
      #
      # Provides Rails-aware concurrency calculation that respects connection pool
      # limits while applying configurable safety margins and pressure factors.
      #
      # @return [Integer] Safe concurrency level for step execution
      def self.intelligent_concurrency_for_step_executor
        health_data = assess_connection_health
        config = Tasker.configuration.execution

        # Get base recommendation from Rails pool analysis
        base_recommendation = health_data[:recommended_concurrency]
        safe_concurrency = apply_tasker_safety_margins(base_recommendation, health_data, config)

        Rails.logger.debug do
          "ConnectionPoolIntelligence: Dynamic concurrency=#{safe_concurrency}, " \
            "pressure=#{health_data[:connection_pressure]}, " \
            "pool_size=#{ActiveRecord::Base.connection_pool.size}, " \
            "available=#{health_data[:rails_pool_stats][:available]}"
        end

        safe_concurrency
      rescue StandardError => e
        Rails.logger.error(
          "ConnectionPoolIntelligence: Concurrency calculation failed - #{e.class.name}: #{e.message}, " \
          "using fallback=#{EMERGENCY_FALLBACK_CONCURRENCY}"
        )

        EMERGENCY_FALLBACK_CONCURRENCY
      end

      private_class_method def self.calculate_utilization(pool_stat)
        return 0.0 if pool_stat[:size].zero?

        (pool_stat[:busy].to_f / pool_stat[:size]).round(CONNECTION_UTILIZATION_PRECISION)
      end

      private_class_method def self.assess_pressure(pool_stat)
        utilization = calculate_utilization(pool_stat)

        # Use CONSTANT thresholds for consistent pressure assessment
        PRESSURE_ASSESSMENT_THRESHOLDS.each do |level, range|
          return level if range.cover?(utilization)
        end

        :unknown
      end

      private_class_method def self.recommend_concurrency(pool_stat)
        pressure = assess_pressure(pool_stat)

        # ✅ CONFIGURABLE: Pressure response factors (environment-dependent)
        pressure_config = Tasker.configuration.execution.connection_pressure_factors
        factor = pressure_config[pressure] || 0.5

        base_recommendation = [pool_stat[:available] * factor, 12].min.floor
        [base_recommendation, EMERGENCY_FALLBACK_CONCURRENCY].max
      end

      private_class_method def self.determine_health_status(pool_stat)
        pressure = assess_pressure(pool_stat)

        case pressure
        when :low, :moderate then :healthy
        when :high then :degraded
        when :critical then :critical
        else :unknown
        end
      end

      private_class_method def self.apply_tasker_safety_margins(base_recommendation, health_data, config)
        # Use CONSTANT safety percentage with CONFIGURABLE bounds
        max_safe = (health_data[:rails_pool_stats][:available] * MAX_SAFE_CONNECTION_PERCENTAGE).floor

        # Apply configurable pressure adjustments based on connection pool state
        pressure_adjusted = case health_data[:connection_pressure]
                            when :moderate
                              [base_recommendation, max_safe].min
                            when :high
                              [base_recommendation * 0.7, max_safe].min.floor
                            when :critical, :unknown
                              [EMERGENCY_FALLBACK_CONCURRENCY, max_safe].min
                            else # :low pressure or any other state
                              base_recommendation
                            end

        # Apply CONFIGURABLE absolute bounds from ExecutionConfig
        pressure_adjusted.clamp(config.min_concurrent_steps, config.max_concurrent_steps_limit)
      end
    end
  end
end
