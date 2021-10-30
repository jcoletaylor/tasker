# typed: false
# frozen_string_literal: true

require 'rails_helper'
require_relative '../../mocks/dummy_task'

module Tasker
  RSpec.describe 'graphql tasks', type: :request do
    before(:all) do
      @factory = Tasker::HandlerFactory.instance
      @handler = @factory.get(DummyTask::TASK_REGISTRY_NAME)
      task_request = TaskRequest.new(name: DummyTask::TASK_REGISTRY_NAME, context: { dummy: true }, initiator: 'pete@test', reason: 'setup test', source_system: 'test')
      @task = @handler.initialize_task!(task_request)
    end

    it 'should get all tasks' do
      post '/graphql', params: { query: all_tasks_query }
      json = JSON.parse(response.body).deep_symbolize_keys
      task_data = json[:data][:tasks]
      expect(task_data.length.positive?).to be_truthy
      task_data.each do |task|
        expect(task[:status]).not_to be_nil
        task[:workflowSteps].each do |step|
          expect(step[:status]).not_to be_nil
        end
        task[:taskAnnotations].each do |annotation|
          expect(annotation[:annotationType][:name]).not_to be_nil
          expect(annotation[:annotation]).not_to be_nil
        end
      end
    end

    it 'should get pending tasks' do
      post '/graphql', params: { query: pending_tasks_query }
      json = JSON.parse(response.body).deep_symbolize_keys
      task_data = json[:data][:tasksByStatus]
      expect(task_data.length.positive?).to be_truthy
      task_data.each do |task|
        expect(task[:status]).to eq('pending')
        task[:workflowSteps].each do |step|
          expect(step[:status]).not_to be_nil
        end
        task[:taskAnnotations].each do |annotation|
          expect(annotation[:annotationType][:name]).not_to be_nil
          expect(annotation[:annotation]).not_to be_nil
        end
      end
    end

    def all_tasks_query
      <<~GQL
        query AllTasks($limit: Int, $offset: Int, $sort_by: String, $sort_order: String) {
          tasks(
            limit: $limit,
            offset: $offset,
            sortBy: $sort_by,
            sortOrder: $sort_order
          ) {
            taskId,
            status,
            workflowSteps {
              workflowStepId,
              status
            },
            taskAnnotations {
              taskAnnotationId,
              annotationType {
                name
              },
              annotation
            }
          }
        }
      GQL
    end

    def pending_tasks_query
      <<~GQL
        query PendingTasks($limit: Int, $offset: Int, $sort_by: String, $sort_order: String) {
          tasksByStatus(
            limit: $limit,
            offset: $offset,
            sortBy: $sort_by,
            sortOrder: $sort_order,
            status: "pending"
          ) {
            taskId,
            status,
            workflowSteps {
              workflowStepId,
              status
            },
            taskAnnotations {
              taskAnnotationId,
              annotationType {
                name
              },
              annotation
            }
          }
        }
      GQL
    end
  end
end
