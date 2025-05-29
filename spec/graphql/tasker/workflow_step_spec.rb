# typed: false
# frozen_string_literal: true

require 'rails_helper'
require_relative '../../mocks/dummy_task'

module Tasker
  RSpec.describe('graphql steps', type: :request) do
    include FactoryWorkflowHelpers

    before(:all) do
      # Register the handler for factory usage
      register_task_handler(DummyTask::TASK_REGISTRY_NAME, DummyTask)

      # Create task using factory approach
      @task = create_dummy_task_workflow(
        context: { dummy: true },
        reason: "setup workflow step test #{Time.now.to_f}",
        initiator: 'pete@test',
        source_system: 'test'
      )

      # Process the task to generate workflow steps
      @factory = Tasker::HandlerFactory.instance
      @handler = @factory.get(DummyTask::TASK_REGISTRY_NAME)
      @handler.handle(@task)
      @task.reload
      @step = @task.workflow_steps.first
    end

    context 'queries' do
      it 'gets a step' do
        post '/tasker/graphql', params: { query: step_query }
        json = JSON.parse(response.body).deep_symbolize_keys
        data = json[:data][:step]
        expect(data[:taskId]).to(eq(@task.task_id))
        expect(Integer(data[:workflowStepId], 10)).to(eq(@step.workflow_step_id))
        expect(data[:processed]).to(be_truthy)
        expect(data[:inProcess]).not_to(be_truthy)
      end
    end

    context 'mutations' do
      context 'update' do
        it 'is able to update a task' do
          post '/tasker/graphql', params: { query: update_step_mutation }
          json = JSON.parse(response.body).deep_symbolize_keys
          data = json[:data][:updateStep]
          expect(data[:retryLimit]).to(eq(22))
        end
      end

      context 'cancel' do
        it 'is able to cancel a task' do
          # Create a separate task with a step in a cancellable state
          cancel_task = create_dummy_task_workflow(
            context: { dummy: true },
            reason: "cancel test workflow step #{Time.now.to_f}",
            initiator: 'pete@test',
            source_system: 'test'
          )

          # Set up step in in_progress state (cancellable)
          cancel_step = cancel_task.workflow_steps.first
          cancel_step.state_machine.transition_to!('in_progress', {
                                                     triggered_by: 'test_setup',
                                                     test: true
                                                   })

          post '/tasker/graphql', params: { query: cancel_step_mutation(cancel_task, cancel_step) }
          json = JSON.parse(response.body).deep_symbolize_keys
          data = json[:data][:cancelStep]
          expect(data[:status]).to(eq('cancelled'))
        end
      end
    end

    def cancel_step_mutation(task = @task, step = @step)
      <<~GQL
        mutation {
          cancelStep(input: {
            taskId: #{task.task_id}
            stepId: #{step.workflow_step_id}
          }) {
            #{step_fields}
          }
        }
      GQL
    end

    def update_step_mutation
      <<~GQL
        mutation {
          updateStep(input: {
            taskId: #{@task.task_id}
            stepId: #{@step.workflow_step_id}
            retryLimit: 22
          }) {
            #{step_fields}
          }
        }
      GQL
    end

    def step_query
      <<~GQL
        query GetOneStep {
          step(
            taskId: #{@task.task_id}
            stepId: #{@step.workflow_step_id}
          ) {
            #{step_fields}
          }
        }
      GQL
    end

    def step_fields
      <<~GQL
        taskId,
        workflowStepId,
        status,
        attempts,
        backoffRequestSeconds,
        inProcess,
        lastAttemptedAt,
        processed,
        processedAt,
        inputs,
        results,
        retryLimit,
        retryable,
        skippable,
        namedStepId,
        parents {
          workflowStepId
        },
        children {
          workflowStepId
        }
      GQL
    end
  end
end
