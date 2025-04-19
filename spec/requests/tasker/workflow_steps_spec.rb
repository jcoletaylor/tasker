# typed: false
# frozen_string_literal: true

require 'swagger_helper'
require_relative '../../mocks/dummy_task'
require_relative '../../mocks/dummy_api_task'
module Tasker
  RSpec.describe 'workflow_steps', type: :request do
    let(:factory) { Tasker::HandlerFactory.instance }
    let(:handler) { factory.get(DummyTask::TASK_REGISTRY_NAME) }
    let(:task_request) { Tasker::Types::TaskRequest.new(name: DummyTask::TASK_REGISTRY_NAME, context: { dummy: true }, initiator: 'pete@test', reason: 'setup workflow step test', source_system: 'test') }
    let(:task_instance) { handler.initialize_task!(task_request) }
    let(:task_id) { task_instance.task_id }

    let(:valid_attributes) do
      { retry_limit: 8 }
    end

    path '/tasker/tasks/{task_id}/workflow_steps' do
      parameter name: 'task_id', in: :path, type: :string, description: 'task_id'

      get('list steps by task') do
        tags 'Steps'
        description 'List Steps by Task'
        operationId 'getStepsByTask'
        produces 'application/json'
        response(200, 'successful') do
          let(:task_id) { task_instance.task_id }

          after do |example|
            example.metadata[:response][:content] = {
              'application/json' => {
                example: JSON.parse(response.body, symbolize_names: true)
              }
            }
          end
          run_test!
        end
      end
    end

    path '/tasker/tasks/{task_id}/workflow_steps/{step_id}' do
      parameter name: 'task_id', in: :path, type: :string, description: 'task_id'
      parameter name: 'step_id', in: :path, type: :string, description: 'step_id'

      get('show step by task') do
        tags 'Steps'
        description 'Show Step by Task'
        operationId 'getStepByTask'
        produces 'application/json'
        consumes 'application/json'
        response(200, 'successful') do
          let(:task_id) { task_instance.task_id }
          let(:step_id) { task_instance.workflow_steps.first.workflow_step_id }

          after do |example|
            example.metadata[:response][:content] = {
              'application/json' => {
                example: JSON.parse(response.body, symbolize_names: true)
              }
            }
          end
          run_test!
        end
      end

      patch('update step by task') do
        tags 'Steps'
        description 'Update Step by Task'
        operationId 'updateStepByTask'
        produces 'application/json'
        consumes 'application/json'
        parameter name: :workflow_step, in: :body, schema: {
          type: :object,
          properties: {
            retry_limit: { type: :integer },
            inputs: { type: :object }
          }
        }
        response(200, 'successful') do
          let(:task_id) { task_instance.task_id }
          let(:step_id) { task_instance.workflow_steps.first.workflow_step_id }
          let(:workflow_step) { { workflow_step: { retry_limit: 10 } } }

          after do |example|
            example.metadata[:response][:content] = {
              'application/json' => {
                example: JSON.parse(response.body, symbolize_names: true)
              }
            }
          end
          run_test! do |_response|
            step = task_instance.workflow_steps.first
            step.reload
            expect(step.retry_limit).to eq(10)
          end
        end
      end

      put('update step by task') do
        tags 'Steps'
        description 'Update Step by Task'
        operationId 'updateStepByTask'
        produces 'application/json'
        consumes 'application/json'
        parameter name: :workflow_step, in: :body, schema: {
          type: :object,
          properties: {
            retry_limit: { type: :integer },
            inputs: { type: :object }
          }
        }
        response(200, 'successful') do
          let(:task_id) { task_instance.task_id }
          let(:step_id) { task_instance.workflow_steps.last.workflow_step_id }
          let(:workflow_step) { { workflow_step: { retry_limit: 8 } } }

          after do |example|
            example.metadata[:response][:content] = {
              'application/json' => {
                example: JSON.parse(response.body, symbolize_names: true)
              }
            }
          end
          run_test! do |_response|
            step = task_instance.workflow_steps.last
            step.reload
            expect(step.retry_limit).to eq(8)
          end
        end
      end

      delete('cancel step by task') do
        tags 'Steps'
        description 'Cancel Step by Task'
        operationId 'cancelStepByTask'
        produces 'application/json'
        consumes 'application/json'
        response(200, 'successful') do
          let(:task_id) { task_instance.task_id }
          let(:step_id) { task_instance.workflow_steps.first.workflow_step_id }

          after do |example|
            example.metadata[:response][:content] = {
              'application/json' => {
                example: JSON.parse(response.body, symbolize_names: true)
              }
            }
          end
          run_test! do |_response|
            step = task_instance.workflow_steps.first
            step.reload
            expect(step.status).to eq('cancelled')
          end
        end
      end
    end
  end
end
