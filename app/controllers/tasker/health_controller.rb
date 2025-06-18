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

    # Set cache headers to prevent caching of health data
    before_action :set_cache_headers

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

    # Detailed status endpoint with comprehensive system metrics
    # Uses system_status.read authorization if authorization is enabled
    #
    # @return [JSON] Detailed system status and metrics
    def status
      result = Tasker::Health::StatusChecker.status

      if result[:healthy]
        render json: result, status: :ok
      else
        render json: result, status: :service_unavailable
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
