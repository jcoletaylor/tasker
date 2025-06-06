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

    let(:invalid_attributes) do
      # missing context
      { name: 'unknown-task' }
    end

    let(:valid_headers) do
      { 'content-type': 'application/json' }
    end

    before do
      # Register the handler for factory usage
      register_task_handler(DummyTask::TASK_REGISTRY_NAME, DummyTask)
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
          run_test!
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
            expect(json_response[:task][:workflow_steps]).not_to be_nil
            expect(json_response[:task][:workflow_steps].length).to eq(4)
            expect(json_response[:task][:workflow_steps].pluck(:status)).to eq(%w[pending pending pending pending])
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
