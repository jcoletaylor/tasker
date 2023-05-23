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

    def shared_task_expectations(task_data)
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

    context 'queries' do
      context 'basic tasks' do
        it 'gets all tasks' do
          post '/tasker/graphql', params: { query: all_tasks_query }
          json = JSON.parse(response.body).deep_symbolize_keys
          task_data = json[:data][:tasks]
          expect(task_data.length).to be_positive
          shared_task_expectations(task_data)
        end

        it 'gets pending tasks' do
          post '/tasker/graphql', params: { query: task_status_query(:pending) }
          json = JSON.parse(response.body).deep_symbolize_keys
          task_data = json[:data][:tasksByStatus]
          expect(task_data.length).to be_positive
          shared_task_expectations(task_data)
          task_data.each do |task|
            expect(task[:status]).to eq('pending')
          end
        end
      end

      context 'annotations' do
        before(:all) do
          task_request = TaskRequest.new(name: DummyTask::TASK_REGISTRY_NAME, context: { dummy: true }, initiator: 'pete@test', reason: 'setup annotations test', source_system: 'test')
          @task = @handler.initialize_task!(task_request)
          @handler.handle(@task)
        end

        it 'gets tasks by annotation when annotation exists' do
          query = tasks_by_annotation_query(annotation_type: 'dummy-annotation', annotation_key: 'step_name', annotation_value: 'step-one')
          post '/tasker/graphql', params: { query: query }
          json = JSON.parse(response.body).deep_symbolize_keys
          task_data = json[:data][:tasksByAnnotation]
          expect(task_data.length).to be_positive
          shared_task_expectations(task_data)
        end

        it 'does not get tasks by annotation when annotation does not exist' do
          query = tasks_by_annotation_query(annotation_type: 'nope', annotation_key: 'nope', annotation_value: 'nope')
          post '/tasker/graphql', params: { query: query }
          json = JSON.parse(response.body).deep_symbolize_keys
          task_data = json[:data][:tasksByAnnotation]
          expect(task_data.length).not_to be_positive
        end
      end
    end

    context 'mutations' do
      context 'create' do
        it 'is able to create a task' do
          post '/tasker/graphql', params: { query: create_task_mutation }
          json = JSON.parse(response.body).deep_symbolize_keys
          task_data = json[:data][:createTask]
          expect(task_data[:taskId]).not_to be_nil
          expect(task_data[:status]).to eq('pending')
        end
      end

      context 'update' do
        it 'is able to update a task' do
          post '/tasker/graphql', params: { query: update_task_mutation }
          json = JSON.parse(response.body).deep_symbolize_keys
          task_data = json[:data][:updateTask]
          expect(task_data[:taskId]).not_to be_nil
          expect(task_data[:reason]).to eq('testing update task mutation')
          expect(task_data[:tags]).to match_array(%w[some great set of tags])
        end
      end

      context 'cancel' do
        it 'is able to cancel a task' do
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

    def task_status_query(status)
      <<~GQL
        query PendingTasks($limit: Int, $offset: Int, $sort_by: String, $sort_order: String) {
          tasksByStatus(
            limit: $limit,
            offset: $offset,
            sortBy: $sort_by,
            sortOrder: $sort_order,
            status: "#{status}"
          ) {
            #{task_fields}
          }
        }
      GQL
    end

    def tasks_by_annotation_query(annotation_type:, annotation_key:, annotation_value:)
      <<~GQL
        query TasksByAnnotation($limit: Int, $offset: Int, $sort_by: String, $sort_order: String) {
          tasksByAnnotation(
            limit: $limit,
            offset: $offset,
            sortBy: $sort_by,
            sortOrder: $sort_order,
            annotationType: "#{annotation_type}",
            annotationKey: "#{annotation_key}",
            annotationValue: "#{annotation_value}"
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
