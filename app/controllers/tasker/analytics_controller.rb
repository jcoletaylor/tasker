# frozen_string_literal: true

require_dependency 'tasker/application_controller'

module Tasker
  # Analytics controller providing performance and bottleneck analysis endpoints.
  #
  # This controller provides analytics endpoints:
  # - `/analytics/performance` - System-wide performance metrics with caching
  # - `/analytics/bottlenecks` - Bottleneck analysis scoped by task/version/namespace
  #
  # All endpoints use the authorization system with appropriate permissions.
  # If authorization is disabled, access is allowed. If enabled, users need
  # the corresponding analytics permissions.
  #
  # Analytics calculations are handled by Tasker::AnalyticsService for better
  # separation of concerns.
  class AnalyticsController < ApplicationController
    # Set cache headers to prevent default caching (we use intelligent caching)
    before_action :set_cache_headers

    # Initialize intelligent cache for expensive analytics operations
    before_action :set_intelligent_cache

    # Performance analytics endpoint with intelligent caching
    # Provides system-wide performance metrics and trends
    #
    # @return [JSON] Performance metrics and analytics
    def performance
      cache_key = "tasker:analytics:performance:#{performance_cache_version}"

      cached_result = @intelligent_cache.intelligent_fetch(cache_key, base_ttl: 90.seconds) do
        performance_analytics = Tasker::AnalyticsService.calculate_performance_analytics

        {
          **performance_analytics.to_h,
          cache_info: {
            cached: true,
            cache_key: cache_key,
            ttl_base: '90 seconds'
          }
        }
      end

      render json: cached_result, status: :ok
    rescue StandardError => e
      render json: {
        error: 'Performance analytics failed',
        message: e.message,
        timestamp: Time.current.iso8601
      }, status: :service_unavailable
    end

    # Bottleneck analysis endpoint scoped by task parameters
    # Provides bottleneck analysis for specific task contexts
    #
    # Query parameters:
    # - namespace: Filter by task namespace (optional)
    # - name: Filter by task name (optional)
    # - version: Filter by task version (optional)
    # - period: Analysis period in hours (default: 24)
    #
    # @return [JSON] Bottleneck analysis for specified scope
    def bottlenecks
      # Extract and validate scope parameters
      scope_params = extract_scope_parameters
      analysis_period = params[:period]&.to_i || 24

      # Generate cache key based on scope and period
      cache_key = "tasker:analytics:bottlenecks:#{bottlenecks_cache_version(scope_params, analysis_period)}"

      cached_result = @intelligent_cache.intelligent_fetch(cache_key, base_ttl: 2.minutes) do
        bottleneck_analytics = Tasker::AnalyticsService.calculate_bottleneck_analytics(
          scope_params,
          analysis_period
        )

        {
          **bottleneck_analytics.to_h,
          cache_info: {
            cached: true,
            cache_key: cache_key,
            ttl_base: '2 minutes'
          }
        }
      end

      render json: cached_result, status: :ok
    rescue StandardError => e
      render json: {
        error: 'Bottleneck analysis failed',
        message: e.message,
        scope: extract_scope_parameters,
        timestamp: Time.current.iso8601
      }, status: :service_unavailable
    end

    private

    def set_intelligent_cache
      @intelligent_cache = Tasker::Telemetry::IntelligentCacheManager.new
    end

    # Extract and validate scope parameters for bottleneck analysis
    #
    # @return [Hash] Validated scope parameters
    def extract_scope_parameters
      scope = {}
      scope[:namespace] = params[:namespace] if params[:namespace].present?
      scope[:name] = params[:name] if params[:name].present?
      scope[:version] = params[:version] if params[:version].present?
      scope
    end

    # Generate cache version for performance analytics
    #
    # @return [String] Cache version that changes when system state changes
    def performance_cache_version
      current_10min_interval = "#{Time.current.strftime('%Y%m%d%H%M')[0..-2]}0" # Round to 10-minute intervals

      # Include recent activity indicators for cache invalidation
      recent_tasks = Task.created_since(30.minutes.ago).count
      recent_completions = WorkflowStep.completed_since(30.minutes.ago).count

      "v1:#{current_10min_interval}:#{recent_tasks}:#{recent_completions}"
    end

    # Generate cache version for bottleneck analysis
    #
    # @param scope_params [Hash] Scope parameters for the analysis
    # @param period [Integer] Analysis period in hours
    # @return [String] Cache version for bottleneck analysis
    def bottlenecks_cache_version(scope_params, period)
      current_10min_interval = "#{Time.current.strftime('%Y%m%d%H%M')[0..-2]}0" # Round to 10-minute intervals
      scope_hash = scope_params.values.join('_').presence || 'all'

      "v1:#{current_10min_interval}:#{scope_hash}:#{period}h"
    end

    # Override the resource name for authorization
    # Maps analytics actions to analytics resource
    #
    # @return [String] The resource name for authorization
    def tasker_resource_name
      Tasker::Authorization::ResourceConstants::RESOURCES::ANALYTICS
    end

    # Override the action name for authorization
    # Maps all actions to index permission for analytics
    #
    # @return [Symbol] The action name for authorization
    def tasker_action_name
      Tasker::Authorization::ResourceConstants::ACTIONS::INDEX
    end

    # Override authentication check for analytics endpoint
    # Uses telemetry configuration for consistency with metrics
    #
    # @return [Boolean] True if authentication should be skipped
    def skip_authentication?
      !Tasker.configuration.telemetry.metrics_auth_required
    end

    # Override authorization check for analytics endpoint
    # Uses telemetry configuration for consistency with metrics
    #
    # @return [Boolean] True if authorization should be skipped
    def skip_authorization?
      !Tasker.configuration.telemetry.metrics_auth_required
    end

    # Set appropriate cache control headers for analytics endpoints
    def set_cache_headers
      response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
      response.headers['Pragma'] = 'no-cache'
      response.headers['Expires'] = '0'
    end
  end
end
