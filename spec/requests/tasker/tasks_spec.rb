# typed: false
# frozen_string_literal: true

require 'swagger_helper'
require_relative '../../mocks/dummy_task'
require_relative '../../mocks/dummy_api_task'
module Tasker
  RSpec.describe 'tasks', type: :request do
    let(:factory) { Tasker::HandlerFactory.instance }
    let(:handler) { factory.get(DummyTask::TASK_REGISTRY_NAME) }
    let(:task_request) { Tasker::Types::TaskRequest.new(name: DummyTask::TASK_REGISTRY_NAME, context: { dummy: true }, initiator: 'pete@test', reason: 'basic test', source_system: 'test') }
    let(:task_instance) { handler.initialize_task!(task_request) }
    let(:task_id) { task_instance.task_id }

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

    path '/tasker/tasks' do
      get('list tasks') do
        tags 'Tasks'
        description 'Lists Tasks'
        operationId 'listTasks'
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
          before do |_example|
            task_instance
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
            expect(json_response[:task][:task_id]).to eq(task_instance.task_id)
            expect(json_response[:task][:workflow_steps]).not_to be_nil
            expect(json_response[:task][:workflow_steps].length).to eq(4)
            expect(json_response[:task][:workflow_steps].pluck(:status)).to eq(%w[pending pending pending pending])
          end
        end
        response(200, 'successful for completed task') do
          before do |_example|
            handler.handle(task_instance)
          end
          run_test! do |response|
            json_response = JSON.parse(response.body).deep_symbolize_keys
            expect(json_response[:task][:task_id]).to eq(task_instance.task_id)
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
          before do |_example|
            task
          end
          let(:task) { { task: { reason: 'patch test', tags: %w[more testing] } } }
          after do |example|
            example.metadata[:response][:content] = {
              'application/json' => {
                example: JSON.parse(response.body, symbolize_names: true)
              }
            }
          end
          run_test! do |_response|
            task_instance.reload
            expect(task_instance.reason).to eq('patch test')
            expect(task_instance.tags).to eq(%w[more testing])
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
          let(:task_id) { task_instance.task_id }
          let(:task) { { task: { reason: 'put test', tags: %w[more testing] } } }
          after do |example|
            example.metadata[:response][:content] = {
              'application/json' => {
                example: JSON.parse(response.body, symbolize_names: true)
              }
            }
          end
          run_test! do |_response|
            task_instance.reload
            expect(task_instance.reason).to eq('put test')
            expect(task_instance.tags).to eq(%w[more testing])
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
          before do |_example|
            @delete_task_instance = handler.initialize_task!(Tasker::Types::TaskRequest.new(valid_attributes.merge({ reason: 'delete test' })))
          end
          let(:task_id) { @delete_task_instance.task_id }

          after do |example|
            example.metadata[:response][:content] = {
              'application/json' => {
                example: JSON.parse(response.body, symbolize_names: true)
              }
            }
          end
          run_test! do |_response|
            @delete_task_instance.reload
            expect(@delete_task_instance.status).to eq(Constants::TaskStatuses::CANCELLED)
          end
        end
      end
    end
  end
end
