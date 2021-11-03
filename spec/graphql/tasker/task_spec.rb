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

    context 'queries' do
      it 'should get all tasks' do
        post '/tasker/graphql', params: { query: all_tasks_query }
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
        post '/tasker/graphql', params: { query: pending_tasks_query }
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
    end

    context 'mutations' do
      context 'create' do
        it 'should be able to create a task' do
          post '/tasker/graphql', params: { query: create_task_mutation }
          json = JSON.parse(response.body).deep_symbolize_keys
          task_data = json[:data][:createTask]
          expect(task_data[:taskId]).not_to be_nil
          expect(task_data[:status]).to eq('pending')
        end
      end
      context 'update' do
        it 'should be able to update a task' do
          post '/tasker/graphql', params: { query: update_task_mutation }
          json = JSON.parse(response.body).deep_symbolize_keys
          task_data = json[:data][:updateTask]
          expect(task_data[:taskId]).not_to be_nil
          expect(task_data[:reason]).to eq('testing update task mutation')
          expect(task_data[:tags]).to match_array(%w[some great set of tags])
        end
      end
      context 'cancel' do
        it 'should be able to cancel a task' do
          post '/tasker/graphql', params: { query: cancel_task_mutation }
          json = JSON.parse(response.body).deep_symbolize_keys
          task_data = json[:data][:cancelTask]
          expect(task_data[:taskId]).not_to be_nil
          expect(task_data[:status]).to eq('cancelled')
        end
      end
    end

    def cancel_task_mutation
      <<~GQL
        mutation {
          cancelTask(input: {
            taskId: #{@task.task_id}
          }) {
            #{task_fields}
          }
        }
      GQL
    end

    def update_task_mutation
      <<~GQL
        mutation {
          updateTask(input: {
            taskId: #{@task.task_id}
            reason: "testing update task mutation"
            tags: ["some", "great", "set", "of", "tags"]
          }) {
            #{task_fields}
          }
        }
      GQL
    end

    def create_task_mutation
      task_request = TaskRequest.new(name: DummyTask::TASK_REGISTRY_NAME, context: { dummy: true }, initiator: 'pete@test', reason: 'mutation test', source_system: 'test')
      <<~GQL
        mutation {
          createTask(input: {
            name: "#{task_request.name}"
            context: #{JSON.generate(task_request.context.to_json)}
            initiator: "#{task_request.initiator}"
            reason: "#{task_request.reason}"
            sourceSystem: "#{task_request.source_system}"
          }) {
            #{task_fields}
          }
        }
      GQL
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
            #{task_fields}
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
            #{task_fields}
          }
        }
      GQL
    end

    def task_fields
      <<~GQL
        taskId,
        status,
        reason,
        tags,
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
      GQL
    end
  end
end
