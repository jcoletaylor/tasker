# typed: false
# frozen_string_literal: true

require 'rails_helper'
require_relative '../mocks/dummy_task'

module Helpers
  class TaskHelpers
    STEP_ONE = 'dummy_step_one'
    STEP_TWO = 'dummy_step_two'
    STEP_THREE = 'dummy_step_three'
    STEP_FOUR = 'dummy_step_four'
    DEPENDENT_SYSTEM = 'dummy-system'
    DUMMY_TASK = 'dummy_task'
    DUMMY_TASK_TWO = 'dummy_task_two'

    def initialize
      factory.register(DUMMY_TASK, DummyTask, replace: true)
      factory.register(DUMMY_TASK_TWO, DummyTask, replace: true)
    end

    def factory
      @factory ||= Tasker::HandlerFactory.instance
    end

    def step_defaults(options = {})
      Tasker::Types::StepTemplate.new(
        {
          name: STEP_ONE,
          status: Tasker::Constants::WorkflowStepStatuses::PENDING,
          retryable: true,
          retry_limit: 3,
          in_process: false,
          processed: false,
          attempts: 0,
          inputs: { dummy: true }
        }.merge(options)
      )
    end

    def task_request(options = {})
      Tasker::Types::TaskRequest.new(
        {
          name: DUMMY_TASK,
          initiator: 'pete@test',
          reason: 'testing!',
          bypass_steps: [],
          source_system: 'test-system',
          context: { dummy: true },
          tags: %w[dummy testing]
        }.merge(options)
      )
    end

    def mark_step_complete(step)
      step.status = Tasker::Constants::WorkflowStepStatuses::COMPLETE
      step.results = { dummy: true, other: true }
      step.processed = true
      step.processed_at = Time.zone.now
      step.in_process = false
      step.save!
      step
    end

    def reset_step_to_default(step)
      step.status = Tasker::Constants::WorkflowStepStatuses::PENDING
      step.results = { dummy: true }
      step.processed = false
      step.processed_at = nil
      step.in_process = false
      step.save!
      step
    end
  end

  class ApiTaskHelpers
    STEP_ONE = 'step-one'
    STEP_TWO = 'step-two'
    STEP_THREE = 'step-three'
    STEP_FOUR = 'step-four'
    DEPENDENT_SYSTEM = 'dummy-system'
    DUMMY_API_TASK = 'dummy_api_task'
    DUMMY_API_TASK_TWO = 'dummy_api_task_two'

    def initialize
      factory.register(DUMMY_API_TASK, DummyApiTask, replace: true)
      factory.register(DUMMY_API_TASK_TWO, DummyApiTask, replace: true)
    end

    def factory
      @factory ||= Tasker::HandlerFactory.instance
    end

    def step_defaults(options = {})
      Tasker::Types::StepTemplate.new(
        {
          name: STEP_ONE,
          status: Tasker::Constants::WorkflowStepStatuses::PENDING,
          retryable: true,
          retry_limit: 3,
          in_process: false,
          processed: false,
          attempts: 0,
          inputs: { dummy: true }
        }.merge(options)
      )
    end

    def task_request(options = {})
      Tasker::Types::TaskRequest.new(
        {
          name: DUMMY_API_TASK,
          initiator: 'pete@test',
          reason: 'testing!',
          bypass_steps: [],
          source_system: DEPENDENT_SYSTEM,
          context: { dummy: true },
          tags: %w[dummy testing]
        }.merge(options)
      )
    end

    def mark_step_complete(step)
      step.status = Tasker::Constants::WorkflowStepStatuses::COMPLETE
      step.results = { dummy: true, other: true }
      step.processed = true
      step.processed_at = Time.zone.now
      step.in_process = false
      step.save!
      step
    end

    def reset_step_to_default(step)
      step.status = Tasker::Constants::WorkflowStepStatuses::PENDING
      step.results = { dummy: true }
      step.processed = false
      step.processed_at = nil
      step.in_process = false
      step.save!
      step
    end
  end
end
