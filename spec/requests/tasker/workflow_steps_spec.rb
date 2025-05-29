# typed: false
# frozen_string_literal: true

require 'swagger_helper'
require_relative '../../mocks/dummy_task'
require_relative '../../mocks/dummy_api_task'
module Tasker
  RSpec.describe 'workflow_steps', type: :request do
    before do
      # Register the handler for factory usage
      register_task_handler(DummyTask::TASK_REGISTRY_NAME, DummyTask)
    end

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
          # Create task specifically for listing steps
          let(:list_steps_task) { create_dummy_task_workflow(context: { dummy: true }, reason: 'list steps test') }
          let(:task_id) { list_steps_task.id }

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
          # Create task specifically for showing step
          let(:show_step_task) { create_dummy_task_workflow(context: { dummy: true }, reason: 'show step test') }
          let(:task_id) { show_step_task.id }
          let(:step_id) { show_step_task.workflow_steps.first.id }

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
          # Create task specifically for patch step test
          let(:patch_step_task) { create_dummy_task_workflow(context: { dummy: true }, reason: 'patch step test') }
          let(:task_id) { patch_step_task.id }
          let(:step_id) { patch_step_task.workflow_steps.first.id }
          let(:workflow_step) { { workflow_step: { retry_limit: 10 } } }

          after do |example|
            example.metadata[:response][:content] = {
              'application/json' => {
                example: JSON.parse(response.body, symbolize_names: true)
              }
            }
          end
          run_test! do |_response|
            step = patch_step_task.workflow_steps.first
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
          # Create task specifically for put step test
          let(:put_step_task) { create_dummy_task_workflow(context: { dummy: true }, reason: 'put step test') }
          let(:task_id) { put_step_task.id }
          let(:step_id) { put_step_task.workflow_steps.last.id }
          let(:workflow_step) { { workflow_step: { retry_limit: 8 } } }

          after do |example|
            example.metadata[:response][:content] = {
              'application/json' => {
                example: JSON.parse(response.body, symbolize_names: true)
              }
            }
          end
          run_test! do |_response|
            step = put_step_task.workflow_steps.last
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
          # Create task specifically for delete step test
          let(:delete_step_task) { create_dummy_task_workflow(context: { dummy: true }, reason: 'delete step test') }
          let(:task_id) { delete_step_task.id }
          let(:step_id) { delete_step_task.workflow_steps.first.id }

          after do |example|
            example.metadata[:response][:content] = {
              'application/json' => {
                example: JSON.parse(response.body, symbolize_names: true)
              }
            }
          end
          run_test! do |_response|
            step = delete_step_task.workflow_steps.first
            step.reload
            expect(step.status).to eq('cancelled')
          end
        end
      end
    end
  end
end
