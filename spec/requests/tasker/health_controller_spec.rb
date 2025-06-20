# frozen_string_literal: true

require 'rails_helper'
require_relative '../../examples/test_authenticator'
require_relative '../../examples/custom_authorization_coordinator'

RSpec.describe Tasker::HealthController, type: :request do
  around do |example|
    # Store original configuration
    original_config = Tasker.configuration.dup

    # Configure basic health settings for tests
    Tasker.configure do |config|
      config.health.cache_duration_seconds = 30
      config.auth.authentication_enabled = false
      config.auth.authorization_enabled = false
    end

    example.run

    # Restore original configuration
    Tasker.instance_variable_set(:@configuration, original_config)
  end

  describe 'GET /health/ready' do
    it 'returns ready status when system is healthy' do
      allow(Tasker::Health::ReadinessChecker).to receive(:ready?).and_return({
        ready: true,
        checks: { database: { status: 'ok' } },
        timestamp: Time.current
      })

      get '/tasker/health/ready'

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to eq('application/json; charset=utf-8')

      json_response = JSON.parse(response.body)
      expect(json_response['ready']).to be true
    end

    it 'returns not ready status when system is unhealthy' do
      allow(Tasker::Health::ReadinessChecker).to receive(:ready?).and_return({
        ready: false,
        checks: { database: { status: 'error', message: 'Connection failed' } },
        timestamp: Time.current
      })

      get '/tasker/health/ready'

      expect(response).to have_http_status(:service_unavailable)
      expect(response.content_type).to eq('application/json; charset=utf-8')

      json_response = JSON.parse(response.body)
      expect(json_response['ready']).to be false
    end

    it 'handles exceptions gracefully' do
      allow(Tasker::Health::ReadinessChecker).to receive(:ready?).and_raise(StandardError.new('Unexpected error'))

      get '/tasker/health/ready'

      expect(response).to have_http_status(:service_unavailable)
      json_response = JSON.parse(response.body)
      expect(json_response['ready']).to be false
      expect(json_response['error']).to eq('Health check failed')
      expect(json_response['message']).to include('Unexpected error')
    end

    it 'never requires authentication or authorization' do
      original_config = Tasker.configuration.dup

      # Configure authentication and authorization as enabled
      Tasker.configure do |config|
        config.auth.authentication_enabled = true
        config.auth.authorization_enabled = true
        config.auth.authenticator_class = 'TestAuthenticator'
        config.auth.authorization_coordinator_class = 'CustomAuthorizationCoordinator'
      end

      allow(Tasker::Health::ReadinessChecker).to receive(:ready?).and_return({
        ready: true,
        checks: {},
        timestamp: Time.current
      })

      # Should work without any authentication/authorization headers
      get '/tasker/health/ready'

      expect(response).to have_http_status(:ok)

      # Restore configuration
      Tasker.instance_variable_set(:@configuration, original_config)
    end
  end

  describe 'GET /health/live' do
    it 'returns alive status' do
      get '/tasker/health/live'

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to eq('application/json; charset=utf-8')

      json_response = JSON.parse(response.body)
      expect(json_response['alive']).to be true
      expect(json_response['service']).to eq('tasker')
      expect(json_response['timestamp']).to be_present
    end

    it 'never requires authentication or authorization' do
      original_config = Tasker.configuration.dup

      # Configure authentication and authorization as enabled
      Tasker.configure do |config|
        config.auth.authentication_enabled = true
        config.auth.authorization_enabled = true
        config.auth.authenticator_class = 'TestAuthenticator'
        config.auth.authorization_coordinator_class = 'CustomAuthorizationCoordinator'
      end

      # Should work without any authentication/authorization headers
      get '/tasker/health/live'

      expect(response).to have_http_status(:ok)

      # Restore configuration
      Tasker.instance_variable_set(:@configuration, original_config)
    end
  end

  describe 'GET /health/status' do
    context 'when authorization is disabled' do
      around do |example|
        original_config = Tasker.configuration.dup

        Tasker.configure do |config|
          config.auth.authorization_enabled = false
        end

        example.run

        Tasker.instance_variable_set(:@configuration, original_config)
      end

      it 'returns healthy status when system is healthy' do
        allow(Tasker::Health::StatusChecker).to receive(:status).and_return({
          healthy: true,
          timestamp: Time.current,
          metrics: { tasks: { total: 0 } },
          database: { active_connections: 1, max_connections: 10, connection_utilization: 10.0 }
        })

        get '/tasker/health/status'

        expect(response).to have_http_status(:ok)
        expect(response.content_type).to eq('application/json; charset=utf-8')

        json_response = JSON.parse(response.body)
        expect(json_response['healthy']).to be true
      end

      it 'returns unhealthy status when system is unhealthy' do
        allow(Tasker::Health::StatusChecker).to receive(:status).and_return({
          healthy: false,
          timestamp: Time.current,
          error: 'Database connection failed'
        })

        get '/tasker/health/status'

        expect(response).to have_http_status(:service_unavailable)
        expect(response.content_type).to eq('application/json; charset=utf-8')

        json_response = JSON.parse(response.body)
        expect(json_response['healthy']).to be false
        expect(json_response['error']).to include('Database connection failed')
      end

      it 'allows access without authentication or authorization' do
        allow(Tasker::Health::StatusChecker).to receive(:status).and_return({
          healthy: true,
          timestamp: Time.current,
          metrics: { tasks: { total: 0 } },
          database: { active_connections: 1, max_connections: 10, connection_utilization: 10.0 }
        })

        get '/tasker/health/status'

        expect(response).to have_http_status(:ok)
      end
    end

    context 'when authorization is enabled' do
      around do |example|
        original_config = Tasker.configuration.dup
        example.run
        Tasker.instance_variable_set(:@configuration, original_config)
      end

      before do
        Tasker.configure do |config|
          config.auth.authentication_enabled = true
          config.auth.authorization_enabled = true
          config.auth.authenticator_class = 'TestAuthenticator'
          config.auth.authorization_coordinator_class = 'CustomAuthorizationCoordinator'
        end

        # Mock successful authentication
        allow_any_instance_of(TestAuthenticator).to receive(:authenticate!).and_return(true)
        allow_any_instance_of(TestAuthenticator).to receive(:authenticated?).and_return(true)

        # Mock healthy status
        allow(Tasker::Health::StatusChecker).to receive(:status).and_return({
          healthy: true,
          timestamp: Time.current,
          metrics: { tasks: { total: 0 } },
          database: { active_connections: 1, max_connections: 10, connection_utilization: 10.0 }
        })
      end

      it 'requires health_status.index authorization' do
        # Mock user without health_status.index permission
        unauthorized_user = double('User',
          id: 1,
          tasker_admin?: false,
          has_tasker_permission?: false
        )
        allow_any_instance_of(TestAuthenticator).to receive(:current_user).and_return(unauthorized_user)

        get '/tasker/health/status', headers: { 'Authorization' => 'Bearer valid-token' }

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

        get '/tasker/health/status', headers: { 'Authorization' => 'Bearer admin-token' }

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['healthy']).to be true
      end

      it 'allows access for users with health_status.index permission' do
        # Mock user with health_status.index permission
        authorized_user = double('User',
          id: 1,
          tasker_admin?: false,
          has_tasker_permission?: ->(permission) { permission == 'tasker.health_status:index' }
        )
        allow_any_instance_of(TestAuthenticator).to receive(:current_user).and_return(authorized_user)

        get '/tasker/health/status', headers: { 'Authorization' => 'Bearer authorized-token' }

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)
        expect(json_response['healthy']).to be true
      end

      it 'handles authorization coordinator errors gracefully' do
        # Mock authorization coordinator error - use the correct error type
        allow_any_instance_of(CustomAuthorizationCoordinator).to receive(:authorize!).and_raise(Tasker::Authorization::ConfigurationError.new('Authorization system error'))

        authorized_user = double('User', id: 1)
        allow_any_instance_of(TestAuthenticator).to receive(:current_user).and_return(authorized_user)

        get '/tasker/health/status', headers: { 'Authorization' => 'Bearer valid-token' }

        expect(response).to have_http_status(:internal_server_error)
        json_response = JSON.parse(response.body)
        expect(json_response['error']).to eq('Authorization Configuration Error')
        expect(json_response['message']).to include('Authorization system error')
      end
    end

    context 'error handling' do
      around do |example|
        original_config = Tasker.configuration.dup

        Tasker.configure do |config|
          config.auth.authorization_enabled = false
        end

        example.run

        Tasker.instance_variable_set(:@configuration, original_config)
      end

      it 'handles status checker exceptions gracefully' do
        allow(Tasker::Health::StatusChecker).to receive(:status).and_raise(StandardError.new('Status error'))

        get '/tasker/health/status'

        expect(response).to have_http_status(:service_unavailable)
        json_response = JSON.parse(response.body)
        expect(json_response['healthy']).to be false
        expect(json_response['error']).to eq('Status check failed')
        expect(json_response['message']).to include('Status error')
      end
    end
  end

  describe 'caching behavior' do
    around do |example|
      Rails.cache.clear
      original_config = Tasker.configuration.dup

      Tasker.configure do |config|
        config.auth.authorization_enabled = false
      end

      example.run

      Tasker.instance_variable_set(:@configuration, original_config)
      Rails.cache.clear
    end

    it 'uses cached results for status endpoint' do
      # Test caching by mocking Rails.cache to track cache operations
      cache_key = nil
      cache_read_count = 0
      cache_write_count = 0
      cache_data = nil

      allow(Rails.cache).to receive(:read) do |key|
        cache_key = key
        cache_read_count += 1
        cache_data
      end

      allow(Rails.cache).to receive(:write) do |key, value, options|
        cache_key = key
        cache_write_count += 1
        cache_data = value
        true
      end

      # First request should miss cache and write to cache
      get '/tasker/health/status'
      first_response = JSON.parse(response.body)

      # Second request should hit cache
      get '/tasker/health/status'
      second_response = JSON.parse(response.body)

      # Both responses should have the same structure (indicating caching worked)
      expect(first_response['metrics']['tasks']['total']).to eq(second_response['metrics']['tasks']['total'])
      expect(cache_read_count).to eq(2) # Cache.read called twice (once for each request)
      expect(cache_write_count).to eq(1) # Cache.write called once (first request only)
      expect(cache_key).to eq('tasker:health:status') # Verify cache key is correct
    end
  end

  describe 'response headers' do
    before do
      Tasker.configure do |config|
        config.auth.authorization_enabled = false
      end
    end

    it 'sets appropriate content type for all endpoints' do
      allow(Tasker::Health::ReadinessChecker).to receive(:ready?).and_return({ ready: true, checks: {}, timestamp: Time.current })
      allow(Tasker::Health::StatusChecker).to receive(:status).and_return({ healthy: true, timestamp: Time.current, metrics: { tasks: { total: 0 } }, database: { active_connections: 1, max_connections: 10, connection_utilization: 10.0 } })

      get '/tasker/health/ready'
      expect(response.content_type).to eq('application/json; charset=utf-8')

      get '/tasker/health/live'
      expect(response.content_type).to eq('application/json; charset=utf-8')

      get '/tasker/health/status'
      expect(response.content_type).to eq('application/json; charset=utf-8')
    end

    it 'sets cache control headers appropriately' do
      allow(Tasker::Health::ReadinessChecker).to receive(:ready?).and_return({ ready: true, checks: {}, timestamp: Time.current })

      get '/tasker/health/ready'
      # Rails may override the header, but it should prevent caching
      expect(response.headers['Cache-Control']).to match(/no-cache|no-store/)
    end
  end
end
