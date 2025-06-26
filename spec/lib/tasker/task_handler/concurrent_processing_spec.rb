# frozen_string_literal: true

require 'rails_helper'

module Tasker
  class TestStepHandler
    class << self
      attr_accessor :executions, :sleep_duration
    end

    @executions = Concurrent::Array.new
    @sleep_duration = 0.2 # Short sleep to allow for observable concurrency

    def self.reset_executions
      @executions = Concurrent::Array.new
    end

    def self.set_sleep_duration(duration)
      @sleep_duration = duration
    end

    def handle(_task, _sequence, step)
      # Record start time
      start_time = Time.now.to_f

      # Simulate some work
      sleep(self.class.sleep_duration)

      # Record that this step ran with timing info
      self.class.executions << {
        step_name: step.name,
        thread_id: Thread.current.object_id,
        start_time: start_time,
        end_time: Time.now.to_f
      }

      # Update step results
      step.results = {
        processed_at: Time.zone.now.to_s,
        thread_id: Thread.current.object_id
      }

      # Return step for chaining
      step
    end
  end

  class ConcurrentTestTask
    include Tasker::TaskHandler

    TASK_NAME = 'concurrent_test_task'
    STEP_ONE = 'step-one'
    STEP_TWO = 'step-two'
    STEP_THREE = 'step-three'

    # Register with concurrent processing enabled
    register_handler(TASK_NAME, concurrent: true)

    define_step_templates do |templates|
      templates.define(
        name: STEP_ONE,
        description: 'Step One',
        handler_class: TestStepHandler
      )

      templates.define(
        name: STEP_TWO,
        description: 'Step Two',
        handler_class: TestStepHandler
      )

      templates.define(
        name: STEP_THREE,
        description: 'Step Three',
        depends_on_steps: [STEP_ONE, STEP_TWO],
        handler_class: TestStepHandler
      )
    end

    # Define a schema for validation
    def schema
      {
        type: 'object',
        properties: {
          test_id: { type: 'integer' }
        }
      }
    end
  end

  class SequentialTestTask
    include Tasker::TaskHandler

    TASK_NAME = 'sequential_test_task'
    STEP_ONE = 'step-one'
    STEP_TWO = 'step-two'

    # Register with concurrent processing disabled
    register_handler(TASK_NAME, concurrent: false)

    define_step_templates do |templates|
      templates.define(
        name: STEP_ONE,
        description: 'Step One',
        handler_class: TestStepHandler
      )

      templates.define(
        name: STEP_TWO,
        description: 'Step Two',
        handler_class: TestStepHandler
      )
    end

    def schema
      {
        type: 'object',
        properties: {
          test_id: { type: 'integer' }
        }
      }
    end
  end

  RSpec.describe TaskHandler do
    describe 'Concurrent Processing' do
      let(:factory) { Tasker::HandlerFactory.instance }
      let(:task_handler) { factory.get(ConcurrentTestTask::TASK_NAME) }
      let(:valid_context) { { test_id: 123 } }

      before do
        Tasker::HandlerFactory.instance.register(ConcurrentTestTask::TASK_NAME, ConcurrentTestTask, replace: true)
        TestStepHandler.reset_executions
      end

      it 'processes independent steps concurrently' do
        # Create a task with two independent steps
        task_request = Tasker::Types::TaskRequest.new(
          name: ConcurrentTestTask::TASK_NAME,
          context: valid_context,
          initiator: 'test_user',
          source_system: 'test_system',
          reason: 'testing concurrent processing'
        )
        task = task_handler.initialize_task!(task_request)

        # Ensure sleep is long enough to observe concurrency
        TestStepHandler.set_sleep_duration(0.2)

        # Process the task which should run steps 1 and 2 concurrently
        task_handler.handle(task)

        # Get the execution details
        executions = TestStepHandler.executions

        # We should have at least 3 executions (steps 1, 2, and 3)
        expect(executions.size).to be >= 3

        # Find step-one and step-two executions
        step_one = executions.find { |e| e[:step_name] == ConcurrentTestTask::STEP_ONE }
        step_two = executions.find { |e| e[:step_name] == ConcurrentTestTask::STEP_TWO }
        step_three = executions.find { |e| e[:step_name] == ConcurrentTestTask::STEP_THREE }

        # Verify they exist
        expect(step_one).not_to be_nil
        expect(step_two).not_to be_nil
        expect(step_three).not_to be_nil

        # Check if step-one and step-two ran in parallel by examining their time overlaps
        step_one_range = [step_one[:start_time], step_one[:end_time]]
        step_two_range = [step_two[:start_time], step_two[:end_time]]

        # Check for overlap between step-one and step-two
        overlap_exists = step_one_range[0] <= step_two_range[1] && step_two_range[0] <= step_one_range[1]
        expect(overlap_exists).to be true

        # Verify that step-three ran after both step-one and step-two
        expect(step_three[:start_time]).to be >= step_one[:end_time]
        expect(step_three[:start_time]).to be >= step_two[:end_time]
      end

      it 'uses different threads for concurrent execution' do
        # Create a task with independent steps
        task_request = Tasker::Types::TaskRequest.new(
          name: ConcurrentTestTask::TASK_NAME,
          context: valid_context,
          initiator: 'test_user',
          source_system: 'test_system',
          reason: 'testing different threads'
        )
        task = task_handler.initialize_task!(task_request)

        # Handle the task
        task_handler.handle(task)

        # Get the execution details
        executions = TestStepHandler.executions

        steps_to_check = [ConcurrentTestTask::STEP_ONE, ConcurrentTestTask::STEP_TWO]

        # Get thread IDs from the first two steps which should run concurrently
        thread_ids = executions.select do |e|
          steps_to_check.include?(e[:step_name])
        end.pluck(:thread_id).uniq

        # If different thread IDs were used, then parallel execution occurred
        expect(thread_ids.size).to be > 1
      end
    end
  end
end
