# typed: false
# frozen_string_literal: true

require 'swagger_helper'
require_relative '../../mocks/dummy_task'
require_relative '../../mocks/dummy_api_task'

module Tasker
  RSpec.describe 'task_diagrams', type: :request, swagger_doc: 'v1/swagger.yaml' do
    before do
      # Register the handler for factory usage
      register_task_handler(DummyTask::TASK_REGISTRY_NAME, DummyTask)
    end

    path '/tasker/tasks/{task_id}/task_diagrams' do
      parameter name: 'task_id', in: :path, type: :integer, description: 'task_id'

      get('get task diagram') do
        tags 'Tasks'
        description 'Get Mermaid task diagram'
        operationId 'getTaskDiagram'
        produces 'application/json', 'text/html'
        parameter name: 'format', in: :query, type: :string, required: false,
                  description: 'Response format (json, html)'

        response(200, 'successful JSON response') do
          # Create task specifically for JSON diagram test
          let(:json_diagram_task) { create_dummy_task_workflow(context: { dummy: true }, reason: 'json diagram test') }
          let(:task_id) { json_diagram_task.id }
          let(:format) { 'json' }

          after do |example|
            example.metadata[:response][:content] = {
              'application/json' => {
                example: JSON.parse(response.body, symbolize_names: true)
              }
            }
          end

          schema type: :object,
                 properties: {
                   nodes: {
                     type: :array,
                     items: {
                       type: :object,
                       properties: {
                         id: { type: :string },
                         label: { type: :string },
                         shape: { type: :string },
                         style: { type: :string },
                         url: { type: :string },
                         attributes: { type: :object }
                       }
                     }
                   },
                   edges: {
                     type: :array,
                     items: {
                       type: :object,
                       properties: {
                         source_id: { type: :string },
                         target_id: { type: :string },
                         label: { type: :string },
                         type: { type: :string },
                         direction: { type: :string },
                         attributes: { type: :object }
                       }
                     }
                   },
                   direction: { type: :string },
                   title: { type: :string },
                   attributes: { type: :object }
                 }

          run_test! do |response|
            json_response = JSON.parse(response.body)
            expect(json_response).to include('nodes', 'edges')
            expect(json_response['direction']).to eq('TD')
            expect(json_response['title']).to include(task_id.to_s)
          end
        end

        response(200, 'successful HTML response') do
          # Create task specifically for HTML diagram test
          let(:html_diagram_task) { create_dummy_task_workflow(context: { dummy: true }, reason: 'html diagram test') }
          let(:task_id) { html_diagram_task.id }
          let(:format) { 'html' }

          run_test! do |response|
            expect(response.body).to include('<!DOCTYPE html>')
            expect(response.body).to include('<div class="tasker-diagram mermaid">')
          end
        end

        response(404, 'task not found') do
          let(:task_id) { 999999 }
          let(:format) { 'json' }

          run_test!
        end
      end
    end
  end
end
