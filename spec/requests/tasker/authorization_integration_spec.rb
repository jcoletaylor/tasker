# frozen_string_literal: true

require 'rails_helper'

require_relative '../../examples/custom_authorization_coordinator'
require_relative '../../examples/test_authenticator'

RSpec.describe 'Authorization Integration', type: :request do
  include_context 'configuration_test_isolation'

  let(:test_user_class) do
    Class.new do
      include Tasker::Concerns::Authorizable

      attr_accessor :id, :permissions, :roles, :admin

      def initialize(id:, permissions: [], roles: [], admin: false)
        @id = id
        @permissions = permissions
        @roles = roles
        @admin = admin
      end

      def admin?
        @admin
      end
    end
  end

  let(:admin_user) do
    test_user_class.new(
      id: 1,
      permissions: [],
      roles: ['admin'],
      admin: true
    )
  end

  let(:regular_user) do
    test_user_class.new(
      id: 2,
      permissions: [
        'tasker.task:index',
        'tasker.task:show',
        'tasker.workflow_step:index',
        'tasker.workflow_step:show',
        'tasker.task_diagram:index',
        'tasker.task_diagram:show'
      ],
      roles: ['user'],
      admin: false
    )
  end

  let(:limited_user) do
    test_user_class.new(
      id: 3,
      permissions: ['tasker.task:index'],
      roles: ['viewer'],
      admin: false
    )
  end

  # Create a real task with workflow steps for testing
  let(:test_task) { create_dummy_task_workflow(context: { dummy: true }, reason: 'authorization test') }

  before do
    # Register the task handler for all tests
    register_task_handler(DummyTask::TASK_REGISTRY_NAME, DummyTask)
  end

  # Helper method to create a task with authorization context
  def create_task_with_auth(user_permissions: [], user_admin: false)
    # Configure test user with the specified permissions
    TestAuthenticator.set_authentication_result(true)
    TestAuthenticator.set_current_user(test_user_class.new(
      id: 1,
      name: 'Test User',
      permissions: user_permissions,
      admin: user_admin
    ))

    # Create task via POST request to test full authorization flow
    post '/tasker/tasks', params: {
      task: {
        name: DummyTask::TASK_REGISTRY_NAME,
        context: { dummy: true },
        initiator: 'test@example.com',
        reason: 'authorization test',
        source_system: 'test'
      }
    }.to_json, headers: { 'Content-Type' => 'application/json' }
  end

  describe 'REST Controllers' do
    describe 'with authorization disabled' do
      before do
        configure_tasker_auth(
          authentication_enabled: false,
          authorization_enabled: false
        )
      end

      it 'allows access to all endpoints without authorization checks' do
        get '/tasker/tasks'
        expect(response).to have_http_status(:ok)

        get "/tasker/tasks/#{test_task.task_id}/workflow_steps"
        expect(response).to have_http_status(:ok)

        get "/tasker/tasks/#{test_task.task_id}/task_diagrams"
        expect(response).to have_http_status(:ok)
      end
    end

    describe 'with authorization enabled and authenticated admin user' do
      before do
        configure_tasker_auth(
          authentication_enabled: true,
          authenticator_class: 'TestAuthenticator',
          authorization_enabled: true,
          authorization_coordinator_class: 'CustomAuthorizationCoordinator'
        )

        TestAuthenticator.set_authentication_result(true)
        TestAuthenticator.set_current_user(admin_user)
      end

      it 'allows admin access to all task endpoints' do
        get '/tasker/tasks'
        expect(response).to have_http_status(:ok)

        get "/tasker/tasks/#{test_task.task_id}"
        expect(response).to have_http_status(:ok)

        post '/tasker/tasks', params: {
          task: {
            name: DummyTask::TASK_REGISTRY_NAME,
            context: { dummy: true },
            initiator: 'admin@test.com',
            reason: 'admin test',
            source_system: 'test'
          }
        }.to_json, headers: { 'Content-Type' => 'application/json' }
        expect(response).to have_http_status(:created)

        patch "/tasker/tasks/#{test_task.task_id}", params: {
          task: { reason: 'admin update' }
        }.to_json, headers: { 'Content-Type' => 'application/json' }
        expect(response).to have_http_status(:ok)

        delete "/tasker/tasks/#{test_task.task_id}"
        expect(response).to have_http_status(:ok)
      end

      it 'allows admin access to all workflow step endpoints' do
        get "/tasker/tasks/#{test_task.task_id}/workflow_steps"
        expect(response).to have_http_status(:ok)

        workflow_step = test_task.workflow_steps.first
        expect(workflow_step).to be_present, "Test task should have workflow steps"

        get "/tasker/tasks/#{test_task.task_id}/workflow_steps/#{workflow_step.workflow_step_id}"
        expect(response).to have_http_status(:ok)

        patch "/tasker/tasks/#{test_task.task_id}/workflow_steps/#{workflow_step.workflow_step_id}", params: {
          workflow_step: { retry_limit: 5 }
        }.to_json, headers: { 'Content-Type' => 'application/json' }
        expect(response).to have_http_status(:ok)

        delete "/tasker/tasks/#{test_task.task_id}/workflow_steps/#{workflow_step.workflow_step_id}"
        expect(response).to have_http_status(:ok)
      end

      it 'allows admin access to task diagrams' do
        get "/tasker/tasks/#{test_task.task_id}/task_diagrams"
        expect(response).to have_http_status(:ok)
      end
    end

    describe 'with authorization enabled and regular user' do
      before do
        configure_tasker_auth(
          authentication_enabled: true,
          authenticator_class: 'TestAuthenticator',
          authorization_enabled: true,
          authorization_coordinator_class: 'CustomAuthorizationCoordinator'
        )

        TestAuthenticator.set_authentication_result(true)
        TestAuthenticator.set_current_user(regular_user)
      end

      it 'allows authorized access to read-only task endpoints' do
        get '/tasker/tasks'
        expect(response).to have_http_status(:ok)

        get "/tasker/tasks/#{test_task.task_id}"
        expect(response).to have_http_status(:ok)
      end

      it 'denies access to write task endpoints' do
        post '/tasker/tasks', params: {
          task: {
            name: DummyTask::TASK_REGISTRY_NAME,
            context: { dummy: true },
            initiator: 'user@test.com',
            reason: 'user test',
            source_system: 'test'
          }
        }.to_json, headers: { 'Content-Type' => 'application/json' }
        expect(response).to have_http_status(:forbidden)

        patch "/tasker/tasks/#{test_task.task_id}", params: {
          task: { reason: 'user update' }
        }.to_json, headers: { 'Content-Type' => 'application/json' }
        expect(response).to have_http_status(:forbidden)

        delete "/tasker/tasks/#{test_task.task_id}"
        expect(response).to have_http_status(:forbidden)
      end

      it 'allows authorized access to read-only workflow step endpoints' do
        get "/tasker/tasks/#{test_task.task_id}/workflow_steps"
        expect(response).to have_http_status(:ok)

        workflow_step = test_task.workflow_steps.first
        expect(workflow_step).to be_present, "Test task should have workflow steps"

        get "/tasker/tasks/#{test_task.task_id}/workflow_steps/#{workflow_step.workflow_step_id}"
        expect(response).to have_http_status(:ok)
      end

      it 'denies access to write workflow step endpoints' do
        workflow_step = test_task.workflow_steps.first
        expect(workflow_step).to be_present, "Test task should have workflow steps"

        patch "/tasker/tasks/#{test_task.task_id}/workflow_steps/#{workflow_step.workflow_step_id}", params: {
          workflow_step: { retry_limit: 5 }
        }.to_json, headers: { 'Content-Type' => 'application/json' }
        expect(response).to have_http_status(:forbidden)

        delete "/tasker/tasks/#{test_task.task_id}/workflow_steps/#{workflow_step.workflow_step_id}"
        expect(response).to have_http_status(:forbidden)
      end

      it 'allows access to task diagrams' do
        get "/tasker/tasks/#{test_task.task_id}/task_diagrams"
        expect(response).to have_http_status(:ok)
      end
    end

    describe 'with authorization enabled and limited user' do
      before do
        configure_tasker_auth(
          authentication_enabled: true,
          authenticator_class: 'TestAuthenticator',
          authorization_enabled: true,
          authorization_coordinator_class: 'CustomAuthorizationCoordinator'
        )

        TestAuthenticator.set_authentication_result(true)
        TestAuthenticator.set_current_user(limited_user)
      end

      it 'allows access only to explicitly permitted endpoints' do
        get '/tasker/tasks'
        expect(response).to have_http_status(:ok)
      end

      it 'denies access to non-permitted task endpoints' do
        get "/tasker/tasks/#{test_task.task_id}"
        expect(response).to have_http_status(:forbidden)

        post '/tasker/tasks', params: {
          task: {
            name: DummyTask::TASK_REGISTRY_NAME,
            context: { dummy: true },
            initiator: 'limited@test.com',
            reason: 'limited test',
            source_system: 'test'
          }
        }
        expect(response).to have_http_status(:forbidden)
      end

      it 'denies access to workflow step endpoints' do
        get "/tasker/tasks/#{test_task.task_id}/workflow_steps"
        expect(response).to have_http_status(:forbidden)

        workflow_step = test_task.workflow_steps.first
        expect(workflow_step).to be_present, "Test task should have workflow steps"

        get "/tasker/tasks/#{test_task.task_id}/workflow_steps/#{workflow_step.workflow_step_id}"
        expect(response).to have_http_status(:forbidden)
      end

      it 'denies access to task diagrams' do
        get "/tasker/tasks/#{test_task.task_id}/task_diagrams"
        expect(response).to have_http_status(:forbidden)
      end
    end

    describe 'with authorization enabled and unauthenticated user' do
      before do
        configure_tasker_auth(
          authentication_enabled: true,
          authenticator_class: 'TestAuthenticator',
          authorization_enabled: true,
          authorization_coordinator_class: 'CustomAuthorizationCoordinator'
        )

        TestAuthenticator.set_authentication_result(false)
        TestAuthenticator.set_current_user(nil)
      end

      it 'returns 401 for task endpoints when unauthenticated' do
        get '/tasker/tasks'
        expect(response).to have_http_status(:unauthorized)

        get "/tasker/tasks/#{test_task.task_id}"
        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns 401 for workflow step endpoints when unauthenticated' do
        get "/tasker/tasks/#{test_task.task_id}/workflow_steps"
        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns 401 for task diagram endpoints when unauthenticated' do
        get "/tasker/tasks/#{test_task.task_id}/task_diagrams"
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GraphQL Controller' do
    describe 'with authorization disabled' do
      before do
        configure_tasker_auth(
          authentication_enabled: false,
          authorization_enabled: false
        )
      end

      it 'allows GraphQL queries without authorization checks' do
        post '/tasker/graphql', params: {
          query: 'query { tasks { taskId status } }'
        }.to_json, headers: { 'Content-Type' => 'application/json' }
        expect(response).to have_http_status(:ok)
      end
    end

    describe 'with authorization enabled and admin user' do
      before do
        configure_tasker_auth(
          authentication_enabled: true,
          authenticator_class: 'TestAuthenticator',
          authorization_enabled: true,
          authorization_coordinator_class: 'CustomAuthorizationCoordinator'
        )

        TestAuthenticator.set_authentication_result(true)
        TestAuthenticator.set_current_user(admin_user)
      end

      it 'allows GraphQL queries for admin user (tasks index)' do
        post '/tasker/graphql', params: {
          query: 'query { tasks { taskId status } }'
        }.to_json, headers: { 'Content-Type' => 'application/json' }
        expect(response).to have_http_status(:ok)
      end

      it 'allows GraphQL mutations for admin user (create task)' do
        post '/tasker/graphql', params: {
          query: 'mutation { createTask(input: { name: "test", context: "{}", initiator: "admin" }) { task { taskId } } }'
        }.to_json, headers: { 'Content-Type' => 'application/json' }
        expect(response).to have_http_status(:ok)
      end

      it 'includes current_user in GraphQL context' do
        post '/tasker/graphql', params: {
          query: 'query { tasks { taskId status } }'
        }.to_json, headers: { 'Content-Type' => 'application/json' }
        expect(response).to have_http_status(:ok)
        # The user should be available in the GraphQL context
        # This would be tested by a custom GraphQL field that accesses context[:current_user]
      end
    end

    describe 'with authorization enabled and limited user' do
      before do
        configure_tasker_auth(
          authentication_enabled: true,
          authenticator_class: 'TestAuthenticator',
          authorization_enabled: true,
          authorization_coordinator_class: 'CustomAuthorizationCoordinator'
        )

        TestAuthenticator.set_authentication_result(true)
        TestAuthenticator.set_current_user(limited_user)
      end

      it 'allows authorized GraphQL queries (tasks index)' do
        post '/tasker/graphql', params: {
          query: 'query { tasks { taskId status } }'
        }.to_json, headers: { 'Content-Type' => 'application/json' }
        expect(response).to have_http_status(:ok)
      end

      it 'denies unauthorized GraphQL mutations (create task)' do
        post '/tasker/graphql', params: {
          query: 'mutation { createTask(input: { name: "test", context: "{}", initiator: "user" }) { task { taskId } } }'
        }.to_json, headers: { 'Content-Type' => 'application/json' }
        expect(response).to have_http_status(:forbidden)
      end
    end

    describe 'with authorization enabled and unauthenticated user' do
      before do
        configure_tasker_auth(
          authentication_enabled: true,
          authenticator_class: 'TestAuthenticator',
          authorization_enabled: true,
          authorization_coordinator_class: 'CustomAuthorizationCoordinator'
        )

        TestAuthenticator.set_authentication_result(false)
        TestAuthenticator.set_current_user(nil)
      end

      it 'returns 401 for GraphQL queries when unauthenticated' do
        post '/tasker/graphql', params: {
          query: 'query { tasks { taskId status } }'
        }.to_json, headers: { 'Content-Type' => 'application/json' }
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'Authorization Error Handling' do
    before do
      configure_tasker_auth(
        authentication_enabled: true,
        authenticator_class: 'TestAuthenticator',
        authorization_enabled: true,
        authorization_coordinator_class: 'CustomAuthorizationCoordinator'
      )

      TestAuthenticator.set_authentication_result(true)
      TestAuthenticator.set_current_user(limited_user)
    end

    it 'handles authorization failures gracefully' do
      get "/tasker/tasks/#{test_task.task_id}"
      expect(response).to have_http_status(:forbidden)

      response_body = JSON.parse(response.body)
      expect(response_body).to have_key('error')
      expect(response_body['error']).to eq('Forbidden')
      expect(response_body).to have_key('message')
    end

    it 'provides meaningful error messages' do
      get "/tasker/tasks/#{test_task.task_id}"
      expect(response).to have_http_status(:forbidden)

      response_body = JSON.parse(response.body)
      expect(response_body['message']).to match(/Not authorized to show on tasker\.task/)
    end
  end

  describe 'Configuration Validation' do
    it 'handles invalid authorization coordinator class' do
      configure_tasker_auth(
        authentication_enabled: true,
        authenticator_class: 'TestAuthenticator',
        authorization_enabled: true,
        authorization_coordinator_class: 'NonExistentCoordinator'
      )

      TestAuthenticator.set_authentication_result(true)
      TestAuthenticator.set_current_user(admin_user)

      get '/tasker/tasks'
      expect(response).to have_http_status(:internal_server_error)

      response_body = JSON.parse(response.body)
      expect(response_body['error']).to eq('Authorization Configuration Error')
      expect(response_body['message']).to match(/NonExistentCoordinator.*not found/)
    end

    it 'validates coordinator interface compliance' do
      # Create an invalid coordinator that doesn't inherit from BaseCoordinator
      invalid_coordinator = Class.new do
        def initialize(user = nil)
          @user = user
        end
      end
      Object.const_set('InvalidCoordinator', invalid_coordinator)

      configure_tasker_auth(
        authentication_enabled: true,
        authenticator_class: 'TestAuthenticator',
        authorization_enabled: true,
        authorization_coordinator_class: 'InvalidCoordinator'
      )

      TestAuthenticator.set_authentication_result(true)
      TestAuthenticator.set_current_user(admin_user)

      get '/tasker/tasks'
      expect(response).to have_http_status(:internal_server_error)

      response_body = JSON.parse(response.body)
      expect(response_body['error']).to match(/Error/)

      Object.send(:remove_const, 'InvalidCoordinator')
    end
  end

  describe 'Resource and Action Validation' do
    before do
      configure_tasker_auth(
        authentication_enabled: true,
        authenticator_class: 'TestAuthenticator',
        authorization_enabled: true,
        authorization_coordinator_class: 'CustomAuthorizationCoordinator'
      )

      TestAuthenticator.set_authentication_result(true)
      TestAuthenticator.set_current_user(admin_user)
    end

    it 'validates resources and actions exist in the registry' do
      # This should pass with valid resource/action combinations
      get '/tasker/tasks'
      expect(response).to have_http_status(:ok)

      get "/tasker/tasks/#{test_task.task_id}/workflow_steps"
      expect(response).to have_http_status(:ok)

      get "/tasker/tasks/#{test_task.task_id}/task_diagrams"
      expect(response).to have_http_status(:ok)
    end
  end

  private

  def configure_tasker_auth(authentication_enabled: false, authenticator_class: nil, authorization_enabled: false, authorization_coordinator_class: nil)
    Tasker.configuration do |config|
      config.auth do |auth|
        auth.authentication_enabled = authentication_enabled
        auth.authenticator_class = authenticator_class if authenticator_class
        auth.authorization_enabled = authorization_enabled
        auth.authorization_coordinator_class = authorization_coordinator_class if authorization_coordinator_class
      end
    end
  end
end
