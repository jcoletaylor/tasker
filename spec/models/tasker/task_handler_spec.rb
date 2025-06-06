# typed: false
# frozen_string_literal: true

require 'rails_helper'
require_relative '../../mocks/dummy_task'

module Tasker
  RSpec.describe(TaskHandler) do
    describe 'DummyTask' do
      let(:factory) { Tasker::HandlerFactory.instance }
      let(:task_handler) { factory.get(DummyTask::TASK_REGISTRY_NAME) }

      before do
        # Register the handler for factory usage
        register_task_handler(DummyTask::TASK_REGISTRY_NAME, DummyTask)
      end

      it 'is able to initialize a dummy task and get the handler' do
        generic_task_handler = DummyTask.new
        expect(generic_task_handler.step_templates.first.handler_class).to(eq(DummyTask::Handler))
      end

      it 'handler factory should be able to find the correct handler' do
        expect(task_handler.step_templates.first.handler_class).to(eq(DummyTask::Handler))
      end

      it 'is able to initialize a task' do
        # Use factory-based task creation instead of manual TaskRequest
        task = create_dummy_task_workflow(context: { dummy: true })

        expect(task).to(be_valid)
        expect(task).to(be_persisted)
        task.reload
        expect(task.workflow_steps.count).to(eq(4))
      end

      it 'is not able to initialize a task if the context is invalid' do
        # Create task with invalid context using factory approach with find_or_create pattern
        dummy_named_task = Tasker::NamedTask.find_or_create_by!(name: 'dummy_task') do |named_task|
          named_task.description = 'Dummy task for testing workflow step logic'
        end

        task = create(:task,
                      named_task: dummy_named_task,
                      context: { bad_param: true, dummy: 12 })

        # Validate the context using the task handler's schema validation
        dummy_task_handler = DummyTask.new
        schema = dummy_task_handler.schema
        validation_errors = JSON::Validator.fully_validate(schema, task.context)

        # Should have validation errors for bad param and wrong type
        expect(validation_errors.length).to(be >= 1)
        expect(validation_errors.join(' ')).to include('dummy')
      end

      it 'is able to initialize and handle a task' do
        # Clean up any existing state from other tests that might interfere
        # This ensures we start with a fresh task rather than working around with unique names
        cleanup_task_state_for_orchestration('dummy_task')

        # Use the factory pattern that creates tasks with proper pending states
        # This ensures steps are created in pending state for orchestration processing
        task = create_dummy_task_for_orchestration(context: { dummy: true })

        # Execute the full workflow using task handler (now delegates to orchestration)
        task_handler.handle(task)
        task.reload

        # Verify all steps completed
        step_states = task.workflow_steps.map(&:status)
        expect(step_states).to(eq(%w[complete complete complete complete]))
        expect(task.task_annotations.count).to(eq(4))

        # Check step dependencies are correctly mapped using factory-created steps
        step_one = find_step_by_name(task, DummyTask::STEP_ONE)
        step_two = find_step_by_name(task, DummyTask::STEP_TWO)
        step_three = find_step_by_name(task, DummyTask::STEP_THREE)
        step_four = find_step_by_name(task, DummyTask::STEP_FOUR)

        expect(step_one.parents.count).to(eq(0))
        expect(step_one.children.count).to(eq(0))

        expect(step_two.parents.count).to(eq(0))
        expect(step_two.children.count).to(eq(1))

        expect(step_three.parents.count).to(eq(1))
        expect(step_three.children.count).to(eq(1))

        expect(step_four.parents.count).to(eq(1))
        expect(step_four.children.count).to(eq(0))

        expect(step_three.parents.first.workflow_step_id).to(eq(step_two.workflow_step_id))
        expect(step_four.parents.first.workflow_step_id).to(eq(step_three.workflow_step_id))
      end
    end
  end
end
