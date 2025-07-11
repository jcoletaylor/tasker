# frozen_string_literal: true

require_dependency 'tasker/application_controller'

module Tasker
  # Metrics controller providing Prometheus-compatible metrics endpoint.
  #
  # This controller provides a single metrics endpoint:
  # - `/tasker/metrics` - Prometheus format metrics (optional authentication)
  #
  # The metrics endpoint uses optional authentication based on the telemetry configuration.
  # If authentication is disabled or telemetry.metrics_auth_required is false, access is allowed.
  # If authentication is enabled, users need the `tasker.metrics:index` permission.
  class MetricsController < ApplicationController
    # Set cache headers to prevent caching of metrics data
    before_action :set_cache_headers

    # Metrics endpoint providing Prometheus-compatible metrics
    # Uses optional authentication based on telemetry configuration
    #
    # @return [Text] Prometheus format metrics or JSON error
    def index
      result = export_metrics

      if result[:success]
        render plain: result[:data], content_type: 'text/plain; charset=utf-8'
      else
        render json: {
          error: 'Metrics export failed',
          message: result[:error],
          timestamp: result[:timestamp]
        }, status: :service_unavailable
      end
    rescue StandardError => e
      render json: {
        error: 'Metrics endpoint failed',
        message: e.message,
        timestamp: Time.current.iso8601
      }, status: :service_unavailable
    end

    private

    # Override the resource name for authorization
    # Maps metrics action to metrics resource
    #
    # @return [String] The resource name for authorization
    def tasker_resource_name
      Tasker::Authorization::ResourceConstants::RESOURCES::METRICS
    end

    # Override the action name for authorization
    # Maps index action to index permission
    #
    # @return [Symbol] The action name for authorization
    def tasker_action_name
      Tasker::Authorization::ResourceConstants::ACTIONS::INDEX
    end

    # Override authentication check for metrics endpoint
    # Uses telemetry configuration instead of global auth configuration
    #
    # @return [Boolean] True if authentication should be skipped
    def skip_authentication?
      !Tasker::Configuration.configuration.telemetry.metrics_auth_required
    end

    # Override authorization check for metrics endpoint
    # Uses telemetry configuration instead of global auth configuration
    #
    # @return [Boolean] True if authorization should be skipped
    def skip_authorization?
      !Tasker::Configuration.configuration.telemetry.metrics_auth_required
    end

    # Export metrics using PrometheusExporter
    #
    # @return [Hash] Export result with success status and data
    def export_metrics
      return disabled_metrics_response unless metrics_enabled?

      exporter = Tasker::Telemetry::PrometheusExporter.new
      exporter.safe_export
    end

    # Check if metrics collection is enabled
    #
    # @return [Boolean] True if metrics are enabled
    def metrics_enabled?
      Tasker::Configuration.configuration.telemetry.metrics_enabled
    end

    # Response when metrics are disabled
    #
    # @return [Hash] Disabled metrics response
    def disabled_metrics_response
      {
        success: false,
        error: 'Metrics collection is disabled',
        timestamp: Time.current.iso8601
      }
    end

    # Set appropriate cache control headers for metrics endpoint
    def set_cache_headers
      response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
      response.headers['Pragma'] = 'no-cache'
      response.headers['Expires'] = '0'
    end
  end
end
