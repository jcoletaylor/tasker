# frozen_string_literal: true

require_dependency 'tasker/application_controller'

module Tasker
  # Health check controller providing endpoints for system health monitoring.
  #
  # This controller provides three health check endpoints:
  # - `/health/ready` - Readiness check (K8s probes, always unauthenticated)
  # - `/health/live` - Liveness check (K8s probes, always unauthenticated)
  # - `/health/status` - Detailed status (uses system_status.read authorization)
  #
  # The status endpoint uses the authorization system with the `system_status.read` permission.
  # If authorization is disabled or no authorization coordinator is configured, access is allowed.
  # If authorization is enabled, users need the `tasker.system_status:read` permission.
  class HealthController < ApplicationController
    # Skip authentication and authorization for K8s probe endpoints
    skip_before_action :authenticate_tasker_user!, only: %i[ready live]
    skip_before_action :authorize_tasker_action!, only: %i[ready live]

    # Set cache headers to prevent caching of health data (except detailed status)
    before_action :set_cache_headers, except: [:status]

    # Initialize intelligent cache for expensive status operations
    before_action :set_intelligent_cache, only: [:status]

    # Readiness check endpoint for Kubernetes probes
    # Always returns quickly and doesn't require authentication/authorization
    #
    # @return [JSON] Simple ready/not ready status
    def ready
      result = Tasker::Health::ReadinessChecker.ready?

      if result[:ready]
        render json: result, status: :ok
      else
        render json: result, status: :service_unavailable
      end
    rescue StandardError => e
      render json: {
        ready: false,
        error: 'Health check failed',
        message: e.message,
        timestamp: Time.current.iso8601
      }, status: :service_unavailable
    end

    # Liveness check endpoint for Kubernetes probes
    # Always returns 200 OK and doesn't require authentication/authorization
    #
    # @return [JSON] Simple alive status
    def live
      render json: {
        alive: true,
        timestamp: Time.current.iso8601,
        service: 'tasker'
      }, status: :ok
    end

    # Detailed status endpoint with comprehensive system metrics (cached)
    # Uses system_status.read authorization if authorization is enabled
    # Results are cached using IntelligentCacheManager for performance
    #
    # @return [JSON] Detailed system status and metrics
    def status
      # Use intelligent caching for expensive system status analysis
      cache_key = "tasker:health:detailed_status:#{system_status_cache_version}"

      cached_result = @intelligent_cache.intelligent_fetch(cache_key, base_ttl: 60.seconds) do
        status_result = Tasker::Health::StatusChecker.status

        # Enhance with additional performance analytics
        enhanced_result = enhance_status_with_analytics(status_result)

        {
          **enhanced_result,
          generated_at: Time.current,
          cache_info: {
            cached: true,
            cache_key: cache_key,
            ttl_base: '5 minutes'
          }
        }
      end

      if cached_result[:healthy]
        render json: cached_result, status: :ok
      else
        render json: cached_result, status: :service_unavailable
      end
    rescue StandardError => e
      render json: {
        healthy: false,
        error: 'Status check failed',
        message: e.message,
        timestamp: Time.current.iso8601
      }, status: :service_unavailable
    end

    private

    def set_intelligent_cache
      @intelligent_cache = Tasker::Telemetry::IntelligentCacheManager.new
    end

    # Generate cache version based on system state for intelligent cache invalidation
    #
    # @return [String] Cache version that changes when system state changes significantly
    def system_status_cache_version
      # Use current hour and basic system metrics for cache versioning
      # This ensures cache invalidation every hour and when major system changes occur
      current_hour = Time.current.strftime('%Y%m%d%H')

      # Include basic system state indicators using scopes
      active_tasks = Task.created_since(1.hour.ago).count
      recent_errors = WorkflowStep.failed_since(1.hour.ago).count

      "v1:#{current_hour}:#{active_tasks}:#{recent_errors}"
    end

    # Enhance basic status with additional performance analytics
    #
    # @param status_result [Hash] Basic status from StatusChecker
    # @return [Hash] Enhanced status with performance insights
    def enhance_status_with_analytics(status_result)
      # Add performance trend analysis
      performance_trends = calculate_performance_trends

      # Add cache performance metrics
      cache_performance = @intelligent_cache.export_performance_metrics

      # Enhance the original status with analytics
      status_result.merge(
        performance_analytics: {
          trends: performance_trends,
          cache_performance: cache_performance,
          analysis_period: '1 hour',
          enhanced_at: Time.current
        }
      )
    rescue StandardError => e
      # If analytics enhancement fails, return original status with error note
      status_result.merge(
        performance_analytics: {
          error: "Analytics enhancement failed: #{e.message}",
          fallback_mode: true
        }
      )
    end

    # Calculate performance trends for the last hour
    #
    # @return [Hash] Performance trend analysis
    def calculate_performance_trends
      one_hour_ago = 1.hour.ago

      {
        task_creation_rate: Task.created_since(one_hour_ago).count,
        completion_rate: Task.completed_since(one_hour_ago).count,
        error_rate: Task.failed_since(one_hour_ago).count,
        avg_step_duration: calculate_average_step_duration(one_hour_ago)
      }
    end

    # Calculate average step duration for performance trending
    #
    # @param since [Time] Calculate duration since this time
    # @return [Float] Average duration in seconds
    def calculate_average_step_duration(since)
      completed_steps = WorkflowStep.completed_since(since)

      return 0.0 if completed_steps.empty?

      durations = completed_steps.filter_map do |step|
        next 0.0 unless step.created_at && step.updated_at

        (step.updated_at - step.created_at).to_f
      end

      durations.empty? ? 0.0 : (durations.sum / durations.size).round(3)
    end

    # Override the resource name for authorization
    # Maps status action to health_status resource instead of health resource
    #
    # @return [String] The resource name for authorization
    def tasker_resource_name
      case action_name
      when 'status'
        Tasker::Authorization::ResourceConstants::RESOURCES::HEALTH_STATUS
      else
        super
      end
    end

    # Override the action name for authorization
    # Maps status action to index action instead of status action
    #
    # @return [Symbol] The action name for authorization
    def tasker_action_name
      case action_name
      when 'status'
        Tasker::Authorization::ResourceConstants::ACTIONS::INDEX
      else
        super
      end
    end

    # Override authentication check for status endpoint
    # Uses health configuration instead of global auth configuration
    #
    # @return [Boolean] True if authentication should be skipped
    def skip_authentication?
      case action_name
      when 'status'
        !Tasker.configuration.health.status_requires_authentication
      else
        super
      end
    end

    # Set appropriate cache control headers for health endpoints
    def set_cache_headers
      response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
      response.headers['Pragma'] = 'no-cache'
      response.headers['Expires'] = '0'
    end
  end
end
