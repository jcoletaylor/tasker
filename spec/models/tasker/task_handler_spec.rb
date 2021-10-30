# typed: false
# frozen_string_literal: true

require 'rails_helper'
require_relative '../../mocks/dummy_task'

module Tasker
  RSpec.describe TaskHandler, type: :model do
    describe 'DummyTask' do
      let(:factory) { Tasker::HandlerFactory.instance }
      let(:task_handler) { factory.get(DummyTask::TASK_REGISTRY_NAME) }

      it 'should be able to initialize a dummy task and get the handler' do
        generic_task_handler = DummyTask.new
        expect(generic_task_handler.step_templates.first.handler_class).to eq(DummyTask::Handler)
      end
      it 'handler factory should be able to find the correct handler' do
        expect(task_handler.step_templates.first.handler_class).to eq(DummyTask::Handler)
      end
      it 'should be able to initialize a task' do
        task_request = TaskRequest.new(name: DummyTask::TASK_REGISTRY_NAME, context: { dummy: true })
        task = task_handler.initialize_task!(task_request)
        expect(task).to be_valid
        expect(task.save).to be_truthy
        task.reload
        expect(task.workflow_steps.count).to eq(4)
      end
      it 'should not be able to initialize a task if the context is invalid' do
        task_request = TaskRequest.new(name: DummyTask::TASK_REGISTRY_NAME, context: { bad_param: true, dummy: 12 })
        task = task_handler.initialize_task!(task_request)
        # bad param and wrong type, two errors
        expect(task.errors[:context].length).to eq(2)
      end
      it 'should be able to initialize and handle a task' do
        task_request = TaskRequest.new(name: DummyTask::TASK_REGISTRY_NAME, context: { dummy: true })
        task = task_handler.initialize_task!(task_request)
        task_handler.handle(task)
        task.reload
        step_states = task.workflow_steps.map(&:status)
        expect(step_states).to eq(%w[complete complete complete complete])
        expect(task.task_annotations.count).to eq(4)
        # check on steps to ensure that the dependencies mapped correctly

        step_two = task.workflow_steps.includes(:named_step).where(named_step: { name: DummyTask::STEP_TWO }).first
        step_three = task.workflow_steps.includes(:named_step).where(named_step: { name: DummyTask::STEP_THREE }).first
        step_four = task.workflow_steps.includes(:named_step).where(named_step: { name: DummyTask::STEP_FOUR }).first

        expect(step_two.depends_on_step_id).to be_nil
        expect(step_three.depends_on_step_id).to eq(step_two.workflow_step_id)
        expect(step_four.depends_on_step_id).to eq(step_three.workflow_step_id)
      end
    end
  end
end
