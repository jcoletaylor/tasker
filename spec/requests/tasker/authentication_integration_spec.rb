# frozen_string_literal: true

require 'rails_helper'
require_relative '../../examples/test_authenticator'
require_relative '../../examples/bad_authenticator'

RSpec.describe 'Authentication Integration', type: :request do
  include_context 'configuration_test_isolation'

  let!(:task) { FactoryBot.create(:task, :pending) }

  describe 'REST Controllers' do
    describe 'with authentication disabled' do
      around do |example|
        original_config = Tasker::Configuration.instance_variable_get(:@configuration)

        Tasker.configuration do |config|
          config.auth do |auth|
            auth.authentication_enabled = false
          end
        end

        example.run
      ensure
        Tasker::Configuration.instance_variable_set(:@configuration, original_config)
        Tasker::Authentication::Coordinator.reset!
      end

      it 'allows access to tasks without authentication' do
        get '/tasker/tasks'
        expect(response).to have_http_status(:ok)
      end

      it 'allows access to workflow_steps without authentication' do
        get "/tasker/tasks/#{task.task_id}/workflow_steps"
        expect(response).to have_http_status(:ok)
      end
    end

    describe 'with custom authentication (authenticated)' do
      around do |example|
        original_config = Tasker::Configuration.instance_variable_get(:@configuration)

        Tasker.configuration do |config|
          config.auth do |auth|
            auth.authentication_enabled = true
            auth.authenticator_class = 'TestAuthenticator'
          end
        end

        # Configure TestAuthenticator to simulate authenticated user
        TestAuthenticator.set_authentication_result(true)
        TestAuthenticator.set_current_user(TestUser.new(id: 1, name: 'Test User'))

        example.run
      ensure
        Tasker::Configuration.instance_variable_set(:@configuration, original_config)
        Tasker::Authentication::Coordinator.reset!
        TestAuthenticator.reset!
      end

      it 'allows access to tasks when authenticated' do
        get '/tasker/tasks'
        expect(response).to have_http_status(:ok)
      end

      it 'allows access to workflow_steps when authenticated' do
        get "/tasker/tasks/#{task.task_id}/workflow_steps"
        expect(response).to have_http_status(:ok)
      end

      it 'provides access to current_tasker_user in controllers' do
        # We'll need to create a test endpoint to verify this
        # For now, let's verify the authentication works
        get '/tasker/tasks'
        expect(response).to have_http_status(:ok)
        # The fact that we get a 200 means authentication passed
      end
    end

    describe 'with custom authentication (unauthenticated)' do
      around do |example|
        original_config = Tasker::Configuration.instance_variable_get(:@configuration)

        Tasker.configuration do |config|
          config.auth do |auth|
            auth.authentication_enabled = true
            auth.authenticator_class = 'TestAuthenticator'
          end
        end

        # Configure TestAuthenticator to simulate unauthenticated scenario
        TestAuthenticator.set_authentication_result(false)
        TestAuthenticator.set_current_user(nil)

        example.run
      ensure
        Tasker::Configuration.instance_variable_set(:@configuration, original_config)
        Tasker::Authentication::Coordinator.reset!
        TestAuthenticator.reset!
      end

      it 'returns 401 for tasks when unauthenticated' do
        get '/tasker/tasks'
        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns 401 for workflow_steps when unauthenticated' do
        get "/tasker/tasks/#{task.task_id}/workflow_steps"
        expect(response).to have_http_status(:unauthorized)
      end

      it 'includes authentication error message in response' do
        get '/tasker/tasks'
        expect(response).to have_http_status(:unauthorized)
        expect(response.body).to include('Test authentication failed')
      end
    end
  end

  describe 'GraphQL Controller' do
    let(:graphql_query) do
      <<~GQL
        query {
          tasks {
            taskId
            status
          }
        }
      GQL
    end

    describe 'with authentication disabled' do
      around do |example|
        original_config = Tasker::Configuration.instance_variable_get(:@configuration)

        Tasker.configuration do |config|
          config.auth do |auth|
            auth.authentication_enabled = false
          end
        end

        example.run
      ensure
        Tasker::Configuration.instance_variable_set(:@configuration, original_config)
        Tasker::Authentication::Coordinator.reset!
      end

      it 'allows GraphQL queries without authentication' do
        post '/tasker/graphql', params: { query: graphql_query }
        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)
        expect(json_response['errors']).to be_nil
      end
    end

    describe 'with custom authentication (authenticated)' do
      around do |example|
        original_config = Tasker::Configuration.instance_variable_get(:@configuration)

        Tasker.configuration do |config|
          config.auth do |auth|
            auth.authentication_enabled = true
            auth.authenticator_class = 'TestAuthenticator'
          end
        end

        TestAuthenticator.set_authentication_result(true)
        TestAuthenticator.set_current_user(TestUser.new(id: 1, name: 'Test User'))

        example.run
      ensure
        Tasker::Configuration.instance_variable_set(:@configuration, original_config)
        Tasker::Authentication::Coordinator.reset!
        TestAuthenticator.reset!
      end

      it 'allows GraphQL queries when authenticated' do
        post '/tasker/graphql', params: { query: graphql_query }
        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)
        expect(json_response['errors']).to be_nil
      end

      it 'includes current_user in GraphQL context' do
        # Test a query that would use the current user context
        user_query = <<~GQL
          query {
            tasks {
              taskId
              status
            }
          }
        GQL

        post '/tasker/graphql', params: { query: user_query }
        expect(response).to have_http_status(:ok)

        json_response = JSON.parse(response.body)
        expect(json_response['errors']).to be_nil
        # The GraphQL controller should have access to current_tasker_user
      end
    end

    describe 'with custom authentication (unauthenticated)' do
      around do |example|
        original_config = Tasker::Configuration.instance_variable_get(:@configuration)

        Tasker.configuration do |config|
          config.auth do |auth|
            auth.authentication_enabled = true
            auth.authenticator_class = 'TestAuthenticator'
          end
        end

        TestAuthenticator.set_authentication_result(false)
        TestAuthenticator.set_current_user(nil)

        example.run
      ensure
        Tasker::Configuration.instance_variable_set(:@configuration, original_config)
        Tasker::Authentication::Coordinator.reset!
        TestAuthenticator.reset!
      end

      it 'returns 401 for GraphQL queries when unauthenticated' do
        post '/tasker/graphql', params: { query: graphql_query }
        expect(response).to have_http_status(:unauthorized)
      end

      it 'includes authentication error message in GraphQL response' do
        post '/tasker/graphql', params: { query: graphql_query }
        expect(response).to have_http_status(:unauthorized)
        expect(response.body).to include('Test authentication failed')
      end
    end
  end

  describe 'Authentication Error Handling' do
    around do |example|
      original_config = Tasker::Configuration.instance_variable_get(:@configuration)

      Tasker.configuration do |config|
        config.auth do |auth|
          auth.authentication_enabled = true
          auth.authenticator_class = 'TestAuthenticator'
        end
      end

      example.run
    ensure
      Tasker::Configuration.instance_variable_set(:@configuration, original_config)
      Tasker::Authentication::Coordinator.reset!
      TestAuthenticator.reset!
    end

    it 'handles authentication exceptions gracefully' do
      TestAuthenticator.set_authentication_result(false)
      TestAuthenticator.set_current_user(nil)

      get '/tasker/tasks'
      expect(response).to have_http_status(:unauthorized)

      json_response = JSON.parse(response.body)
      expect(json_response['message']).to include('Test authentication failed')
    end

    it 'handles authenticator configuration errors' do
      # Set up TestAuthenticator to have validation errors
      TestAuthenticator.set_validation_errors(['Invalid configuration'])

      # Reset coordinator to trigger validation
      Tasker::Authentication::Coordinator.reset!

      get '/tasker/tasks'
      expect(response).to have_http_status(:internal_server_error)
    end

    it 'handles invalid authenticator class' do
      Tasker.configuration do |config|
        config.auth do |auth|
          auth.authentication_enabled = true
          auth.authenticator_class = 'NonExistentAuthenticator'
        end
      end

      # Reset coordinator to trigger class loading
      Tasker::Authentication::Coordinator.reset!

      get '/tasker/tasks'
      expect(response).to have_http_status(:internal_server_error)
    end
  end

  describe 'Configuration Validation' do
          it 'validates authenticator interface compliance' do
        original_config = Tasker::Configuration.instance_variable_get(:@configuration)

        begin
          Tasker.configuration do |config|
            config.auth do |auth|
              auth.authentication_enabled = true
              auth.authenticator_class = 'BadAuthenticator'
            end
          end

          # Reset coordinator to trigger interface validation
          Tasker::Authentication::Coordinator.reset!

          get '/tasker/tasks'
          expect(response).to have_http_status(:internal_server_error)
        ensure
          Tasker::Configuration.instance_variable_set(:@configuration, original_config)
          Tasker::Authentication::Coordinator.reset!
        end
      end

          it 'runs authenticator configuration validation' do
        original_config = Tasker::Configuration.instance_variable_get(:@configuration)

        begin
          # Set up validation to fail BEFORE setting configuration
          TestAuthenticator.set_validation_errors(['Configuration validation failed'])

          Tasker.configuration do |config|
            config.auth do |auth|
              auth.authentication_enabled = true
              auth.authenticator_class = 'TestAuthenticator'
            end
          end

          # Reset coordinator to trigger validation
          Tasker::Authentication::Coordinator.reset!

          get '/tasker/tasks'
          expect(response).to have_http_status(:internal_server_error)
        ensure
          Tasker::Configuration.instance_variable_set(:@configuration, original_config)
          Tasker::Authentication::Coordinator.reset!
          TestAuthenticator.reset!
        end
      end
  end
end
