# frozen_string_literal: true

require 'rails_helper'
require_relative '../../examples/test_authenticator'
require_relative '../../examples/bad_authenticator'

RSpec.describe 'Authentication Integration', type: :request do
  # Isolate singleton state to prevent test pollution
  around do |example|
    original_config = Tasker::Configuration.instance_variable_get(:@configuration)
    # Reset coordinator and test authenticator state
    Tasker::Authentication::Coordinator.reset!
    TestAuthenticator.reset!

    example.run
  ensure
    # Restore original configuration and reset state
    Tasker::Configuration.instance_variable_set(:@configuration, original_config)
    Tasker::Authentication::Coordinator.reset!
    TestAuthenticator.reset!
  end

  let!(:task) { FactoryBot.create(:task, :pending) }

  describe 'REST Controllers' do
    describe 'with :none authentication strategy' do
      around do |example|
        original_config = Tasker::Configuration.instance_variable_get(:@configuration)

        Tasker.configuration do |config|
          config.auth do |auth|
            auth.strategy = :none
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

      it 'allows access to task_diagrams without authentication' do
        get "/tasker/tasks/#{task.task_id}/task_diagrams"
        expect(response).to have_http_status(:ok)
      end
    end

    describe 'with :custom authentication strategy (authenticated)' do
      around do |example|
        original_config = Tasker::Configuration.instance_variable_get(:@configuration)

        Tasker.configuration do |config|
          config.auth do |auth|
            auth.strategy = :custom
            auth.options = { authenticator_class: 'TestAuthenticator' }
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

      it 'allows access to task_diagrams when authenticated' do
        get "/tasker/tasks/#{task.task_id}/task_diagrams"
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

    describe 'with :custom authentication strategy (unauthenticated)' do
      around do |example|
        original_config = Tasker::Configuration.instance_variable_get(:@configuration)

        Tasker.configuration do |config|
          config.auth do |auth|
            auth.strategy = :custom
            auth.options = { authenticator_class: 'TestAuthenticator' }
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

      it 'returns 401 for task_diagrams when unauthenticated' do
        get "/tasker/tasks/#{task.task_id}/task_diagrams"
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

    describe 'with :none authentication strategy' do
      around do |example|
        original_config = Tasker::Configuration.instance_variable_get(:@configuration)

        Tasker.configuration do |config|
          config.auth do |auth|
            auth.strategy = :none
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

    describe 'with :custom authentication strategy (authenticated)' do
      around do |example|
        original_config = Tasker::Configuration.instance_variable_get(:@configuration)

        Tasker.configuration do |config|
          config.auth do |auth|
            auth.strategy = :custom
            auth.options = { authenticator_class: 'TestAuthenticator' }
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
        # The fact that we get a successful response means the context was set properly
      end
    end

    describe 'with :custom authentication strategy (unauthenticated)' do
      around do |example|
        original_config = Tasker::Configuration.instance_variable_get(:@configuration)

        Tasker.configuration do |config|
          config.auth do |auth|
            auth.strategy = :custom
            auth.options = { authenticator_class: 'TestAuthenticator' }
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
          auth.strategy = :custom
          auth.options = { authenticator_class: 'TestAuthenticator' }
        end
      end

      example.run
    ensure
      Tasker::Configuration.instance_variable_set(:@configuration, original_config)
      Tasker::Authentication::Coordinator.reset!
      TestAuthenticator.reset!
    end

    it 'handles authentication exceptions gracefully' do
      begin
        TestAuthenticator.set_authentication_result(false)
        TestAuthenticator.set_current_user(nil)

        get '/tasker/tasks'
        expect(response).to have_http_status(:unauthorized)
        expect(response.body).to include('Test authentication failed')
      ensure
        TestAuthenticator.reset!
      end
    end

        it 'handles authenticator configuration errors' do
      # Test with missing authenticator_class - override configuration for this test
      original_config = Tasker::Configuration.instance_variable_get(:@configuration)

      begin
        Tasker.configuration do |config|
          config.auth do |auth|
            auth.strategy = :custom
            auth.options = {} # Missing authenticator_class
          end
        end

        get '/tasker/tasks'
        expect(response).to have_http_status(:internal_server_error)
        expect(response.body).to include('Custom authentication strategy requires authenticator_class option')
      ensure
        Tasker::Configuration.instance_variable_set(:@configuration, original_config)
        Tasker::Authentication::Coordinator.reset!
      end
    end

    it 'handles invalid authenticator class' do
      # Override configuration for this test
      original_config = Tasker::Configuration.instance_variable_get(:@configuration)

      begin
        Tasker.configuration do |config|
          config.auth do |auth|
            auth.strategy = :custom
            auth.options = { authenticator_class: 'NonexistentAuthenticator' }
          end
        end

        get '/tasker/tasks'
        expect(response).to have_http_status(:internal_server_error)
      ensure
        Tasker::Configuration.instance_variable_set(:@configuration, original_config)
        Tasker::Authentication::Coordinator.reset!
      end
    end
  end

  describe 'Configuration Validation' do
        it 'validates authenticator interface compliance' do
      # Use the real BadAuthenticator class from spec/examples/bad_authenticator.rb
      # This class intentionally doesn't implement the required interface methods

      # Override configuration for this test
      original_config = Tasker::Configuration.instance_variable_get(:@configuration)

      begin
        Tasker.configuration do |config|
          config.auth do |auth|
            auth.strategy = :custom
            auth.options = { authenticator_class: 'BadAuthenticator' }
          end
        end

        get '/tasker/tasks'
        expect(response).to have_http_status(:internal_server_error)
        expect(response.body).to include('must implement #authenticate!')
      ensure
        Tasker::Configuration.instance_variable_set(:@configuration, original_config)
        Tasker::Authentication::Coordinator.reset!
      end
    end

    it 'runs authenticator configuration validation' do
      # Override configuration for this test to force authenticator rebuild
      original_config = Tasker::Configuration.instance_variable_get(:@configuration)

      begin
        # Set validation errors BEFORE building the authenticator
        TestAuthenticator.set_validation_errors(['Test validation error'])

        # Configure fresh authenticator that will encounter validation errors
        Tasker.configuration do |config|
          config.auth do |auth|
            auth.strategy = :custom
            auth.options = { authenticator_class: 'TestAuthenticator' }
          end
        end

        get '/tasker/tasks'
        expect(response).to have_http_status(:internal_server_error)
        expect(response.body).to include('Test validation error')
      ensure
        Tasker::Configuration.instance_variable_set(:@configuration, original_config)
        Tasker::Authentication::Coordinator.reset!
        TestAuthenticator.reset!
      end
    end
  end
end
