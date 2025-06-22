# typed: false
# frozen_string_literal: true

require 'swagger_helper'
require_relative '../../mocks/dummy_task'
require_relative '../../mocks/dummy_api_task'

module Tasker
  RSpec.describe 'tasks', type: :request do
    let(:valid_attributes) do
      { name: DummyTask::TASK_REGISTRY_NAME, context: { dummy: true }, initiator: 'pete@test', reason: 'basic test', source_system: 'test' }
    end

    let(:valid_attributes_with_namespace) do
      {
        name: DummyTask::TASK_REGISTRY_NAME,
        namespace: 'testing',
        version: '1.0.0',
        context: { dummy: true },
        initiator: 'pete@test',
        reason: 'namespace test',
        source_system: 'test'
      }
    end

    let(:invalid_attributes) do
      # missing context
      { name: 'unknown-task' }
    end

    let(:valid_headers) do
      { 'content-type': 'application/json' }
    end

    # Test handler class for namespace testing
    let(:namespaced_test_handler) do
      Class.new do
        def self.name
          'NamespacedTestHandler'
        end

        def step_templates
          [
            Tasker::Types::StepTemplate.new(
              name: 'namespaced_step',
              dependent_system: 'test_system',
              description: 'A namespaced test step',
              handler_class: String,
              depends_on_step: nil
            )
          ]
        end

        def initialize_task!(task_request)
          named_task = Tasker::NamedTask.find_or_create_by_full_name!(
            namespace_name: task_request.namespace,
            name: task_request.name,
            version: task_request.version
          )

          task = Tasker::Task.create!(
            named_task: named_task,
            context: task_request.context,
            initiator: task_request.initiator,
            reason: task_request.reason,
            source_system: task_request.source_system,
            tags: task_request.tags,
            bypass_steps: task_request.bypass_steps,
            requested_at: task_request.requested_at
          )

          task
        end
      end
    end

    before do
      # Create the testing namespace for the test
      Tasker::TaskNamespace.find_or_create_by!(name: 'testing')

      # Register the handler for factory usage
      register_task_handler(DummyTask::TASK_REGISTRY_NAME, DummyTask)

      # Register namespaced test handler
      handler_factory = Tasker::HandlerFactory.instance
      handler_factory.register(DummyTask::TASK_REGISTRY_NAME, namespaced_test_handler, namespace_name: :testing, version: '1.0.0')
    end

    path '/tasker/tasks' do
      get('list tasks') do
        tags 'Tasks'
        description 'Lists Tasks'
        operationId 'listTasks'
        produces 'application/json'
        response(200, 'successful') do
          # Create a task specifically for listing
          before do
            @list_task = create_dummy_task_workflow(context: { dummy: true }, reason: 'list test')
          end

          after do |example|
            example.metadata[:response][:content] = {
              'application/json' => {
                example: JSON.parse(response.body, symbolize_names: true)
              }
            }
          end
          run_test! do |response|
            json_response = JSON.parse(response.body).deep_symbolize_keys
            expect(json_response[:tasks].pluck(:name)).to include(DummyTask::TASK_REGISTRY_NAME)

            # Check that tasks now include namespace and version information
            task_with_details = json_response[:tasks].find { |t| t[:name] == DummyTask::TASK_REGISTRY_NAME }
            expect(task_with_details[:namespace]).to eq('default')
            expect(task_with_details[:version]).to eq('0.1.0')
            expect(task_with_details[:full_name]).to eq('default.dummy_task@0.1.0')
          end
        end
      end

      post('create and enqueue task') do
        tags 'Tasks'
        description 'Create and Enqueue Task'
        operationId 'createTask'
        produces 'application/json'
        consumes 'application/json'
        parameter name: :task, in: :body, schema: {
          type: :object,
          properties: {
            name: { type: :string },
            namespace: { type: :string },
            version: { type: :string },
            context: { type: :object },
            initiator: { type: :string },
            reason: { type: :string },
            source_system: { type: :string },
            tags: {
              type: :array,
              items: :string
            }
          },
          required: %w[name context]
        }
        response(201, 'successful') do
          after do |example|
            example.metadata[:response][:content] = {
              'application/json' => {
                example: JSON.parse(response.body, symbolize_names: true)
              }
            }
          end
          let(:task) { { task: valid_attributes.dup.merge({ reason: 'post test' }) } }
          run_test! do |response|
            json_response = JSON.parse(response.body).deep_symbolize_keys
            task_data = json_response[:task]
            expect(task_data[:namespace]).to eq('default')
            expect(task_data[:version]).to eq('0.1.0')
            expect(task_data[:full_name]).to eq('default.dummy_task@0.1.0')
          end
        end

        response(201, 'successful with namespace and version') do
          let(:task) { { task: valid_attributes_with_namespace } }

          run_test! do |response|
            json_response = JSON.parse(response.body).deep_symbolize_keys
            task_data = json_response[:task]
            expect(task_data[:name]).to eq(DummyTask::TASK_REGISTRY_NAME)
            expect(task_data[:namespace]).to eq('testing')
            expect(task_data[:version]).to eq('1.0.0')
            expect(task_data[:full_name]).to eq('testing.dummy_task@1.0.0')
            expect(task_data[:reason]).to eq('namespace test')
          end
        end

        response(400, 'bad request') do
          after do |example|
            example.metadata[:response][:content] = {
              'application/json' => {
                example: JSON.parse(response.body, symbolize_names: true)
              }
            }
          end
          let(:task) { { task: { bad: :data } } }
          run_test!
        end

        response(400, 'bad request - handler not found') do
          let(:task) { { task: { name: 'nonexistent_handler', namespace: 'nonexistent', version: '1.0.0', context: { test: true } } } }

          run_test! do |response|
            json_response = JSON.parse(response.body).deep_symbolize_keys
            expect(json_response[:error]).to be_present
          end
        end

        response(400, 'bad request') do
          let(:task) do
            { task: valid_attributes.merge({ context: { bad_param: true, dummy: 99 } }) }
          end
          run_test! do |response|
            json_response = JSON.parse(response.body).deep_symbolize_keys
            expect(json_response[:error][:context]).not_to be_nil
          end
        end
      end
    end

    path '/tasker/tasks/{task_id}' do
      parameter name: 'task_id', in: :path, type: :integer, description: 'task_id'

      get('show task') do
        tags 'Tasks'
        description 'Show Task'
        operationId 'getTask'
        produces 'application/json'
        parameter name: :include_dependencies, in: :query, type: :boolean, required: false, description: 'Include dependency analysis'

        response(200, 'successful') do
          # Create task specifically for this test
          let(:dummy_task) { create_dummy_task_workflow(context: { dummy: true }, reason: 'show test') }
          let(:task_id) { dummy_task.id }

          after do |example|
            example.metadata[:response][:content] = {
              'application/json' => {
                example: JSON.parse(response.body, symbolize_names: true)
              }
            }
          end
          run_test! do |response|
            json_response = JSON.parse(response.body).deep_symbolize_keys
            expect(json_response[:task][:task_id]).to eq(dummy_task.id)
            expect(json_response[:task][:namespace]).to eq('default')
            expect(json_response[:task][:version]).to eq('0.1.0')
            expect(json_response[:task][:full_name]).to eq('default.dummy_task@0.1.0')
            expect(json_response[:task][:workflow_steps]).not_to be_nil
            expect(json_response[:task][:workflow_steps].length).to eq(4)
            expect(json_response[:task][:workflow_steps].pluck(:status)).to eq(%w[pending pending pending pending])
          end
        end

        response(200, 'successful with dependency analysis') do
          let(:dummy_task) { create_dummy_task_workflow(context: { dummy: true }, reason: 'dependency test') }
          let(:task_id) { dummy_task.id }
          let(:include_dependencies) { true }

          run_test! do |response|
            json_response = JSON.parse(response.body).deep_symbolize_keys
            expect(json_response[:task][:task_id]).to eq(dummy_task.id)
            expect(json_response[:task][:dependency_analysis]).to be_present

            # Verify the full dependency analysis structure
            dependency_analysis = json_response[:task][:dependency_analysis]
            expect(dependency_analysis[:dependency_graph]).to be_present
            expect(dependency_analysis[:critical_paths]).to be_present
            expect(dependency_analysis[:parallelism_opportunities]).to be_present
            expect(dependency_analysis[:error_chains]).to be_present
            expect(dependency_analysis[:bottlenecks]).to be_present
            expect(dependency_analysis[:analysis_timestamp]).to be_present
            expect(dependency_analysis[:task_execution_summary]).to be_present

            # Verify task execution summary structure
            summary = dependency_analysis[:task_execution_summary]
            expect(summary[:total_steps]).to be_a(Integer)
            expect(summary[:total_dependencies]).to be_a(Integer)
            expect(summary[:dependency_levels]).to be_a(Integer)
            expect(summary[:longest_path_length]).to be_a(Integer)
            expect(summary[:critical_bottlenecks_count]).to be_a(Integer)
            expect(summary[:error_chains_count]).to be_a(Integer)
            expect(summary[:parallelism_efficiency]).to be_a(Numeric)
            expect(summary[:overall_health]).to be_in(['healthy', 'warning', 'critical'])
            expect(summary[:recommendations]).to be_an(Array)

            # Verify dependency graph structure
            graph = dependency_analysis[:dependency_graph]
            expect(graph[:nodes]).to be_an(Array)
            expect(graph[:edges]).to be_an(Array)
            expect(graph[:adjacency_list]).to be_a(Hash)
            expect(graph[:reverse_adjacency_list]).to be_a(Hash)
            expect(graph[:dependency_levels]).to be_a(Hash)
          end
        end

        response(200, 'dependency analysis error handling') do
          let(:dummy_task) { create_dummy_task_workflow(context: { dummy: true }, reason: 'error test') }
          let(:task_id) { dummy_task.id }
          let(:include_dependencies) { true }

          before do
            # Mock the dependency_graph method to raise an error
            allow_any_instance_of(Tasker::Task).to receive(:dependency_graph).and_raise(StandardError, 'Test analysis error')
          end

          run_test! do |response|
            json_response = JSON.parse(response.body).deep_symbolize_keys
            expect(json_response[:task][:task_id]).to eq(dummy_task.id)
            expect(json_response[:task][:dependency_analysis]).to be_present
            expect(json_response[:task][:dependency_analysis][:error]).to include('Test analysis error')
            expect(json_response[:task][:dependency_analysis][:analysis_timestamp]).to be_present
          end
        end

        response(200, 'successful for completed task') do
          # Use factory approach with completed task
          let(:completed_task) { create_dummy_task_workflow(context: { dummy: true }, reason: 'completed test') }
          let(:task_id) { completed_task.id }

          before do |_example|
            # Complete the task using the state machine approach
            handler = DummyTask.new
            handler.handle(completed_task)
          end

          run_test! do |response|
            json_response = JSON.parse(response.body).deep_symbolize_keys
            expect(json_response[:task][:task_id]).to eq(completed_task.id)
            expect(json_response[:task][:namespace]).to eq('default')
            expect(json_response[:task][:version]).to eq('0.1.0')
            expect(json_response[:task][:full_name]).to eq('default.dummy_task@0.1.0')
            expect(json_response[:task][:task_annotations]).not_to be_nil
            expect(json_response[:task][:task_annotations].length).to eq(4)
          end
        end
      end

      patch('update task') do
        tags 'Tasks'
        description 'Update Task'
        operationId 'updateTask'
        produces 'application/json'
        consumes 'application/json'
        parameter name: :task, in: :body, schema: {
          type: :object,
          properties: {
            reason: { type: :string },
            tags: {
              type: :array,
              items: :string
            }
          }
        }
        response(200, 'successful') do
          # Create task specifically for patch test
          let(:patch_task) { create_dummy_task_workflow(context: { dummy: true }, reason: 'patch base') }
          let(:task_id) { patch_task.id }
          let(:task) { { task: { reason: 'patch test', tags: %w[more testing] } } }

          after do |example|
            example.metadata[:response][:content] = {
              'application/json' => {
                example: JSON.parse(response.body, symbolize_names: true)
              }
            }
          end
          run_test! do |_response|
            patch_task.reload
            expect(patch_task.reason).to eq('patch test')
            expect(patch_task.tags).to eq(%w[more testing])
          end
        end
      end

      put('update task') do
        tags 'Tasks'
        description 'Update Task'
        operationId 'updateTask'
        produces 'application/json'
        consumes 'application/json'
        parameter name: :task, in: :body, schema: {
          type: :object,
          properties: {
            reason: { type: :string },
            tags: {
              type: :array,
              items: :string
            }
          }
        }
        response(200, 'successful') do
          # Create task specifically for put test
          let(:put_task) { create_dummy_task_workflow(context: { dummy: true }, reason: 'put base') }
          let(:task_id) { put_task.id }
          let(:task) { { task: { reason: 'put test', tags: %w[more testing] } } }

          after do |example|
            example.metadata[:response][:content] = {
              'application/json' => {
                example: JSON.parse(response.body, symbolize_names: true)
              }
            }
          end
          run_test! do |_response|
            put_task.reload
            expect(put_task.reason).to eq('put test')
            expect(put_task.tags).to eq(%w[more testing])
          end
        end
      end

      delete('cancel task') do
        tags 'Tasks'
        description 'Cancel Task'
        operationId 'cancelTask'
        produces 'application/json'
        consumes 'application/json'
        response(200, 'successful') do
          # Use factory approach for delete test task
          let(:delete_task) { create_dummy_task_workflow(context: { dummy: true }, reason: 'delete test') }
          let(:task_id) { delete_task.id }

          after do |example|
            example.metadata[:response][:content] = {
              'application/json' => {
                example: JSON.parse(response.body, symbolize_names: true)
              }
            }
          end
          run_test! do |_response|
            delete_task.reload
            expect(delete_task.status).to eq(Constants::TaskStatuses::CANCELLED)
          end
        end
      end
    end
  end
end
