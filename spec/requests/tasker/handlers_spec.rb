# typed: false
# frozen_string_literal: true

require 'swagger_helper'
require_relative '../../mocks/dummy_task'

module Tasker
  RSpec.describe '/tasker/handlers', type: :request do
    let(:valid_headers) do
      { 'content-type': 'application/json' }
    end

    # Test handler classes for namespacing
    let(:test_handler_class) do
      Class.new do
        def self.name
          'TestHandlerClass'
        end

        def step_templates
          [
            Tasker::Types::StepTemplate.new(
              name: 'test_step',
              dependent_system: 'test_api',
              description: 'Test step',
              handler_class: String,
              handler_config: { timeout: 30 }
            )
          ]
        end
      end
    end

    let(:payment_handler_class) do
      Class.new do
        def self.name
          'PaymentHandlerClass'
        end

        def step_templates
          [
            Tasker::Types::StepTemplate.new(
              name: 'validate_payment',
              dependent_system: 'payment_api',
              description: 'Validate payment details',
              handler_class: String,
              handler_config: { timeout: 30 }
            ),
            Tasker::Types::StepTemplate.new(
              name: 'process_payment',
              dependent_system: 'payment_api',
              description: 'Process the payment',
              handler_class: String,
              handler_config: { retry_limit: 3 },
              depends_on_step: 'validate_payment'
            )
          ]
        end
      end
    end

    before do
      # Register test handlers in different namespaces
      handler_factory = Tasker::HandlerFactory.instance

      # Default namespace handlers
      handler_factory.register('test_handler', test_handler_class, namespace_name: :default, version: '0.1.0')
      handler_factory.register('test_handler', test_handler_class, namespace_name: :default, version: '1.0.0')
      handler_factory.register('test_handler', test_handler_class, namespace_name: :default, version: '2.0.0')

      # Payment namespace handlers
      handler_factory.register('process_payment', payment_handler_class, namespace_name: :payments, version: '0.1.0')
      handler_factory.register('process_payment', payment_handler_class, namespace_name: :payments, version: '1.0.0')
      handler_factory.register('process_payment', payment_handler_class, namespace_name: :payments, version: '1.1.0')

      # Register dummy task for consistency
      register_task_handler(DummyTask::TASK_REGISTRY_NAME, DummyTask)
    end

    path '/tasker/handlers' do
      get('list all namespaces') do
        tags 'Handlers'
        description 'Lists all registered namespaces with handler counts'
        operationId 'listNamespaces'
        produces 'application/json'

        response(200, 'successful') do
          after do |example|
            example.metadata[:response][:content] = {
              'application/json' => {
                example: JSON.parse(response.body, symbolize_names: true)
              }
            }
          end

          run_test! do |response|
            json_response = JSON.parse(response.body).deep_symbolize_keys
            expect(json_response[:namespaces]).to be_an(Array)
            expect(json_response[:total_namespaces]).to be > 0

            # Check that default and payments namespaces are included
            namespace_names = json_response[:namespaces].pluck(:name)
            expect(namespace_names).to include('default', 'payments')

            # Check namespace structure
            default_namespace = json_response[:namespaces].find { |ns| ns[:name] == 'default' }
            expect(default_namespace[:handler_count]).to be > 0

            payments_namespace = json_response[:namespaces].find { |ns| ns[:name] == 'payments' }
            expect(payments_namespace[:handler_count]).to eq(1)
          end
        end
      end
    end

    path '/tasker/handlers/{namespace}' do
      parameter name: 'namespace', in: :path, type: :string, description: 'Handler namespace'

      get('list handlers in namespace') do
        tags 'Handlers'
        description 'Lists all handlers in a specific namespace with their versions'
        operationId 'listHandlersInNamespace'
        produces 'application/json'

        response(200, 'successful - default namespace') do
          let(:namespace) { 'default' }

          after do |example|
            example.metadata[:response][:content] = {
              'application/json' => {
                example: JSON.parse(response.body, symbolize_names: true)
              }
            }
          end

          run_test! do |response|
            json_response = JSON.parse(response.body).deep_symbolize_keys
            expect(json_response[:namespace]).to eq('default')
            expect(json_response[:handlers]).to be_an(Array)
            expect(json_response[:total_handlers]).to be > 0

            # Check that test_handler is included
            handler_names = json_response[:handlers].pluck(:name)
            expect(handler_names).to include('test_handler')

            # Check handler structure
            test_handler = json_response[:handlers].find { |h| h[:name] == 'test_handler' }
            expect(test_handler[:namespace]).to eq('default')
            expect(test_handler[:versions]).to include('0.1.0', '1.0.0', '2.0.0')
            expect(test_handler[:latest_version]).to eq('2.0.0')
            expect(test_handler[:handler_count]).to eq(3)
          end
        end

        response(200, 'successful - payments namespace') do
          let(:namespace) { 'payments' }

          run_test! do |response|
            json_response = JSON.parse(response.body).deep_symbolize_keys
            expect(json_response[:namespace]).to eq('payments')
            expect(json_response[:handlers]).to be_an(Array)
            expect(json_response[:total_handlers]).to eq(1)

            # Check payment handler
            payment_handler = json_response[:handlers].first
            expect(payment_handler[:name]).to eq('process_payment')
            expect(payment_handler[:namespace]).to eq('payments')
            expect(payment_handler[:versions]).to include('0.1.0', '1.0.0', '1.1.0')
            expect(payment_handler[:latest_version]).to eq('1.1.0')
          end
        end

        response(404, 'namespace not found') do
          let(:namespace) { 'nonexistent_namespace' }

          after do |example|
            example.metadata[:response][:content] = {
              'application/json' => {
                example: JSON.parse(response.body, symbolize_names: true)
              }
            }
          end

          run_test! do |response|
            json_response = JSON.parse(response.body).deep_symbolize_keys
            expect(json_response[:error]).to eq('Namespace not found')
          end
        end
      end
    end

    path '/tasker/handlers/{namespace}/{name}' do
      parameter name: 'namespace', in: :path, type: :string, description: 'Handler namespace'
      parameter name: 'name', in: :path, type: :string, description: 'Handler name'

      get('show handler with dependency graph') do
        tags 'Handlers'
        description 'Show a specific handler with full details including dependency graph'
        operationId 'getHandlerWithDependencies'
        produces 'application/json'
        parameter name: :version, in: :query, type: :string, required: false, description: 'Handler version'

        response(200, 'successful - simple handler') do
          let(:namespace) { 'default' }
          let(:name) { 'test_handler' }

          after do |example|
            example.metadata[:response][:content] = {
              'application/json' => {
                example: JSON.parse(response.body, symbolize_names: true)
              }
            }
          end

          run_test! do |response|
            json_response = JSON.parse(response.body).deep_symbolize_keys
            handler_data = json_response[:handler]

            # Check basic handler information
            expect(handler_data[:name]).to eq('test_handler')
            expect(handler_data[:namespace]).to eq('default')
            expect(handler_data[:version]).to eq('0.1.0')
            expect(handler_data[:class_name]).to eq('TestHandlerClass')
            expect(handler_data[:step_templates]).to be_an(Array)

            # Check dependency graph
            expect(handler_data[:dependency_graph]).to be_a(Hash)
            expect(handler_data[:dependency_graph][:nodes]).to be_an(Array)
            expect(handler_data[:dependency_graph][:edges]).to be_an(Array)
            expect(handler_data[:dependency_graph][:execution_order]).to be_an(Array)

            # Check dependency graph content
            nodes = handler_data[:dependency_graph][:nodes]
            expect(nodes.size).to eq(1)
            expect(nodes.first[:name]).to eq('test_step')
            expect(nodes.first[:type]).to eq('step')
          end
        end

        response(200, 'successful - complex handler with dependencies') do
          let(:namespace) { 'payments' }
          let(:name) { 'process_payment' }
          let(:version) { '1.1.0' }

          run_test! do |response|
            json_response = JSON.parse(response.body).deep_symbolize_keys
            handler_data = json_response[:handler]

            # Check basic handler information
            expect(handler_data[:name]).to eq('process_payment')
            expect(handler_data[:namespace]).to eq('payments')
            expect(handler_data[:version]).to eq('1.1.0')
            expect(handler_data[:step_templates]).to be_an(Array)
            expect(handler_data[:step_templates].length).to eq(2)

            # Check dependency graph
            dependency_graph = handler_data[:dependency_graph]
            expect(dependency_graph[:nodes]).to be_an(Array)
            expect(dependency_graph[:edges]).to be_an(Array)
            expect(dependency_graph[:execution_order]).to be_an(Array)

            # Check nodes
            expect(dependency_graph[:nodes].size).to eq(2)
            node_names = dependency_graph[:nodes].pluck(:name)
            expect(node_names).to include('validate_payment', 'process_payment')

            # Check edges (dependencies)
            expect(dependency_graph[:edges].size).to eq(1)
            edge = dependency_graph[:edges].first
            expect(edge[:from]).to eq('validate_payment')
            expect(edge[:to]).to eq('process_payment')
            expect(edge[:type]).to eq('dependency')

            # Check execution order
            expect(dependency_graph[:execution_order]).to eq(['validate_payment', 'process_payment'])
          end
        end

        response(404, 'handler not found in namespace') do
          let(:namespace) { 'payments' }
          let(:name) { 'nonexistent_handler' }

          after do |example|
            example.metadata[:response][:content] = {
              'application/json' => {
                example: JSON.parse(response.body, symbolize_names: true)
              }
            }
          end

          run_test! do |response|
            json_response = JSON.parse(response.body).deep_symbolize_keys
            expect(json_response[:error]).to eq('Handler not found in namespace')
          end
        end

        response(404, 'namespace not found') do
          let(:namespace) { 'nonexistent_namespace' }
          let(:name) { 'any_handler' }

          run_test! do |response|
            json_response = JSON.parse(response.body).deep_symbolize_keys
            expect(json_response[:error]).to eq('Namespace not found')
          end
        end
      end
    end

    # Authorization tests
    context 'when authentication is required' do
      before do
        # Enable authentication for these tests by mocking skip_authentication? to return false
        allow_any_instance_of(Tasker::HandlersController).to receive(:skip_authentication?).and_return(false)
        # Mock the authentication method to raise an error
        allow_any_instance_of(Tasker::HandlersController).to receive(:authenticate_tasker_user!).and_raise(Tasker::Authentication::AuthenticationError, 'Authentication required')
      end

      path '/tasker/handlers' do
        get('list namespaces - authentication required') do
          tags 'Handlers'
          response(401, 'unauthorized') do
            run_test! do |response|
              json_response = JSON.parse(response.body).deep_symbolize_keys
              expect(json_response[:error]).to eq('Unauthorized')
              expect(json_response[:message]).to eq('Authentication required')
            end
          end
        end
      end
    end
  end
end
