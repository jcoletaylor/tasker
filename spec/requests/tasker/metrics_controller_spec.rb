# frozen_string_literal: true

require 'rails_helper'
require_relative '../../examples/test_authenticator'
require_relative '../../examples/custom_authorization_coordinator'

RSpec.describe Tasker::MetricsController, type: :request do
  around do |example|
    # Store original configuration
    original_config = Tasker.configuration.dup

    # Configure basic telemetry settings for tests
    Tasker.configure do |config|
      config.telemetry do |telemetry|
        telemetry.metrics_enabled = true
        telemetry.metrics_auth_required = false
      end
      config.auth do |auth|
        auth.authentication_enabled = false
        auth.authorization_enabled = false
      end
    end

    example.run

    # Restore original configuration
    Tasker.instance_variable_set(:@configuration, original_config)
  end

  describe 'GET /tasker/metrics' do
    context 'when metrics are enabled and available' do
      before do
        # Mock successful metrics export
        backend = Tasker::Telemetry::MetricsBackend.instance
        allow(backend).to receive(:export).and_return({
          timestamp: '2023-06-23T10:39:42Z',
          total_metrics: 2,
          metrics: {
            'task_completed_total' => {
              name: 'task_completed_total',
              type: :counter,
              value: 125,
              labels: { status: 'success' }
            },
            'active_connections' => {
              name: 'active_connections',
              type: :gauge,
              value: 5,
              labels: {}
            }
          }
        })
        # Total metrics provided by export method
      end

      it 'returns metrics in Prometheus format' do
        get '/tasker/metrics'

        expect(response).to have_http_status(:ok)
        expect(response.content_type).to eq('text/plain; charset=utf-8')

        response_body = response.body
        expect(response_body).to include('# Tasker metrics export')
        expect(response_body).to include('# GENERATED 2023-06-23T10:39:42Z')
        expect(response_body).to include('# TOTAL_METRICS 2')
        expect(response_body).to include('task_completed_total{status="success"} 125')
        expect(response_body).to include('active_connections 5')
      end

      it 'sets appropriate cache control headers' do
        get '/tasker/metrics'

        expect(response.headers['Cache-Control']).to match(/no-cache|no-store/)
        expect(response.headers['Pragma']).to eq('no-cache')
        expect(response.headers['Expires']).to eq('0')
      end
    end

    context 'when metrics are disabled' do
      around do |example|
        Tasker.configure do |config|
          config.telemetry do |telemetry|
            telemetry.metrics_enabled = false
          end
        end

        example.run
      end

      it 'returns error response' do
        get '/tasker/metrics'

        expect(response).to have_http_status(:service_unavailable)
        expect(response.content_type).to eq('application/json; charset=utf-8')

        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Metrics export failed')
        expect(json_response['message']).to eq('Metrics collection is disabled')
        expect(json_response['timestamp']).to be_present
      end
    end

    context 'when metrics export fails' do
      before do
        backend = Tasker::Telemetry::MetricsBackend.instance
        allow(backend).to receive(:export).and_raise(StandardError, 'Export error')
      end

      it 'returns error response' do
        get '/tasker/metrics'

        expect(response).to have_http_status(:service_unavailable)
        expect(response.content_type).to eq('application/json; charset=utf-8')

        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Metrics export failed')
        expect(json_response['message']).to eq('Export error')
        expect(json_response['timestamp']).to be_present
      end
    end

    context 'when controller throws exception' do
      before do
        # Mock PrometheusExporter to raise exception
        allow_any_instance_of(Tasker::Telemetry::PrometheusExporter).to receive(:safe_export).and_raise(StandardError, 'Controller error')
      end

      it 'handles exceptions gracefully' do
        get '/tasker/metrics'

        expect(response).to have_http_status(:service_unavailable)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Metrics endpoint failed')
        expect(json_response['message']).to include('Controller error')
      end
    end

    context 'when no metrics are available' do
      before do
        backend = Tasker::Telemetry::MetricsBackend.instance
        allow(backend).to receive(:export).and_return({
          timestamp: '2023-06-23T10:39:42Z',
          total_metrics: 0,
          metrics: {}
        })
        # Total metrics provided by export method
      end

      it 'returns empty metrics export' do
        get '/tasker/metrics'

        expect(response).to have_http_status(:ok)
        expect(response.body).to eq("")
      end
    end
  end

  describe 'authentication and authorization' do
    context 'when authentication is disabled' do
      around do |example|
        Tasker.configure do |config|
          config.auth do |auth|
            auth.authentication_enabled = false
            auth.authorization_enabled = false
          end
          config.telemetry do |telemetry|
            telemetry.metrics_auth_required = false
          end
        end

        example.run
      end

      it 'allows access without authentication' do
        # Mock successful metrics
        backend = Tasker::Telemetry::MetricsBackend.instance
        allow(backend).to receive(:export).and_return({
          timestamp: '2023-06-23T10:39:42Z',
          total_metrics: 1,
          metrics: {
            'test_metric' => {
              name: 'test_metric',
              type: :counter,
              value: 1,
              labels: {}
            }
          }
        })
        # Total metrics provided by export method

        get '/tasker/metrics'

        expect(response).to have_http_status(:ok)
      end
    end

    context 'when metrics authentication is required' do
      around do |example|
        Tasker.configure do |config|
          config.auth do |auth|
            auth.authentication_enabled = true
            auth.authorization_enabled = true
            auth.authenticator_class = 'TestAuthenticator'
            auth.authorization_coordinator_class = 'CustomAuthorizationCoordinator'
          end
          config.telemetry do |telemetry|
            telemetry.metrics_auth_required = true
          end
        end

        example.run
      end

      before do
        # Mock successful authentication
        allow_any_instance_of(TestAuthenticator).to receive(:authenticate!).and_return(true)
        allow_any_instance_of(TestAuthenticator).to receive(:authenticated?).and_return(true)

        # Mock successful metrics
        backend = Tasker::Telemetry::MetricsBackend.instance
        allow(backend).to receive(:export).and_return({
          timestamp: '2023-06-23T10:39:42Z',
          total_metrics: 1,
          metrics: {
            'test_metric' => {
              name: 'test_metric',
              type: :counter,
              value: 1,
              labels: {}
            }
          }
        })
        # Total metrics provided by export method
      end

      it 'requires metrics.index authorization' do
        # Mock user without metrics.index permission
        unauthorized_user = double('User',
          id: 1,
          tasker_admin?: false,
          has_tasker_permission?: false
        )
        allow_any_instance_of(TestAuthenticator).to receive(:current_user).and_return(unauthorized_user)

        get '/tasker/metrics', headers: { 'Authorization' => 'Bearer valid-token' }

        expect(response).to have_http_status(:forbidden)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Forbidden')
        expect(json_response['message']).to be_present
      end

      it 'allows access for admin users' do
        # Mock admin user
        admin_user = double('User',
          id: 1,
          tasker_admin?: true,
          has_tasker_permission?: false
        )
        allow_any_instance_of(TestAuthenticator).to receive(:current_user).and_return(admin_user)

        get '/tasker/metrics', headers: { 'Authorization' => 'Bearer admin-token' }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('test_metric 1')
      end

      it 'allows access for users with metrics.index permission' do
        # Mock user with metrics.index permission
        authorized_user = double('User',
          id: 1,
          tasker_admin?: false,
          has_tasker_permission?: ->(permission) { permission == 'tasker.metrics:index' }
        )
        allow_any_instance_of(TestAuthenticator).to receive(:current_user).and_return(authorized_user)

        get '/tasker/metrics', headers: { 'Authorization' => 'Bearer authorized-token' }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('test_metric 1')
      end

      it 'handles authorization coordinator errors gracefully' do
        # Mock authorization coordinator error
        allow_any_instance_of(CustomAuthorizationCoordinator).to receive(:authorize!).and_raise(Tasker::Authorization::ConfigurationError.new('Authorization system error'))

        authorized_user = double('User', id: 1)
        allow_any_instance_of(TestAuthenticator).to receive(:current_user).and_return(authorized_user)

        get '/tasker/metrics', headers: { 'Authorization' => 'Bearer valid-token' }

        expect(response).to have_http_status(:internal_server_error)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Authorization Configuration Error')
        expect(json_response['message']).to include('Authorization system error')
      end
    end

    context 'when metrics auth is disabled but global auth is enabled' do
      around do |example|
        Tasker.configure do |config|
          config.auth do |auth|
            auth.authentication_enabled = true
            auth.authorization_enabled = true
            auth.authenticator_class = 'TestAuthenticator'
            auth.authorization_coordinator_class = 'CustomAuthorizationCoordinator'
          end
          config.telemetry do |telemetry|
            telemetry.metrics_auth_required = false  # Metrics auth disabled
          end
        end

        example.run
      end

      it 'allows access without authentication (metrics auth takes precedence)' do
        # Mock successful metrics
        backend = Tasker::Telemetry::MetricsBackend.instance
        allow(backend).to receive(:export).and_return({
          timestamp: '2023-06-23T10:39:42Z',
          total_metrics: 1,
          metrics: {
            'test_metric' => {
              name: 'test_metric',
              type: :counter,
              value: 1,
              labels: {}
            }
          }
        })
        # Total metrics provided by export method

        # Should work without any authentication headers
        get '/tasker/metrics'

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('test_metric 1')
      end
    end
  end

  describe 'content type and headers' do
    before do
      # Mock successful metrics
      backend = Tasker::Telemetry::MetricsBackend.instance
      allow(backend).to receive(:export).and_return({
        timestamp: '2023-06-23T10:39:42Z',
        total_metrics: 1,
        metrics: {
          'test_metric' => {
            name: 'test_metric',
            type: :counter,
            value: 1,
            labels: {}
          }
        }
      })
      # Total metrics provided by export method
    end

    it 'sets correct content type for successful metrics' do
      get '/tasker/metrics'
      expect(response.content_type).to eq('text/plain; charset=utf-8')
    end

    it 'sets JSON content type for errors' do
      allow_any_instance_of(Tasker::Telemetry::PrometheusExporter).to receive(:safe_export).and_return({
        success: false,
        error: 'Test error',
        timestamp: Time.current.iso8601
      })

      get '/tasker/metrics'
      expect(response.content_type).to eq('application/json; charset=utf-8')
    end

    it 'sets cache control headers to prevent caching' do
      get '/tasker/metrics'

      expect(response.headers['Cache-Control']).to eq('no-store')
      expect(response.headers['Pragma']).to eq('no-cache')
      expect(response.headers['Expires']).to eq('0')
    end
  end
end
