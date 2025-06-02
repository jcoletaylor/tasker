# frozen_string_literal: true

require 'rails_helper'
require_relative '../../../mocks/dummy_task'

RSpec.describe Tasker::StepHandler::Base do
  include FactoryWorkflowHelpers

  before do
    # Register the handler for testing (follows existing patterns)
    register_task_handler(DummyTask::TASK_REGISTRY_NAME, DummyTask)
  end

  # Test step handler that implements the process method (CORRECT PATTERN)
  class TestStepHandler < Tasker::StepHandler::Base
    attr_reader :execution_result

    def process(_task, _sequence, step)
      @execution_result = 'test_result'
      step.results = { test: 'success' }
    end
  end

  # Test step handler that raises an exception (CORRECT PATTERN)
  class FailingStepHandler < Tasker::StepHandler::Base
    def process(_task, _sequence, _step)
      raise StandardError, 'Test error'
    end
  end

  let(:task) { create_dummy_task_workflow(context: { dummy: true }, reason: 'automatic event publishing test') }
  let(:step) { task.workflow_steps.first }
  let(:task_handler) { Tasker::HandlerFactory.instance.get(DummyTask::TASK_REGISTRY_NAME) }
  let(:sequence) { task_handler.get_sequence(task) }

  describe 'automatic event publishing around process method execution' do
    context 'with successful step execution' do
      let(:handler) { TestStepHandler.new }

      before do
        # Spy on event publishing methods to verify they're called
        allow(handler).to receive(:publish_step_started)
        allow(handler).to receive(:publish_step_completed)
        allow(handler).to receive(:publish_event)
      end

      it 'automatically publishes step_started and step_completed events around process() method' do
        handler.handle(task, sequence, step)

        expect(handler).to have_received(:publish_step_started).with(step)
        expect(handler).to have_received(:publish_step_completed).with(step)
      end

      it 'publishes BEFORE_HANDLE event for compatibility' do
        handler.handle(task, sequence, step)

        expect(handler).to have_received(:publish_event).with(
          Tasker::Constants::StepEvents::BEFORE_HANDLE,
          hash_including(
            task_id: task.task_id,
            step_id: step.workflow_step_id,
            step_name: step.name
          )
        )
      end

      it 'executes the developer business logic correctly' do
        handler.handle(task, sequence, step)

        expect(handler.execution_result).to eq('test_result')
        expect(step.results).to eq({ 'test' => 'success' })
      end

      it 'maintains step state correctly during framework coordination' do
        handler.handle(task, sequence, step)

        # Step should maintain its database state
        expect(step.workflow_step_id).to be_present
        expect(step.task_id).to eq(task.task_id)
        expect(step.name).to eq(DummyTask::STEP_ONE)
      end
    end

    context 'with failing step execution' do
      let(:handler) { FailingStepHandler.new }

      before do
        # Spy on event publishing methods to verify they're called
        allow(handler).to receive(:publish_step_started)
        allow(handler).to receive(:publish_step_failed)
        allow(handler).to receive(:publish_event)
      end

      it 'automatically publishes step_started and step_failed events when process() fails' do
        expect do
          handler.handle(task, sequence, step)
        end.to raise_error(StandardError, 'Test error')

        expect(handler).to have_received(:publish_step_started).with(step)
        expect(handler).to have_received(:publish_step_failed).with(step, error: instance_of(StandardError))
      end

      it 're-raises the original exception from developer process() method' do
        expect do
          handler.handle(task, sequence, step)
        end.to raise_error(StandardError, 'Test error')
      end

      it 'preserves step data integrity during error in framework coordination' do
        expect do
          handler.handle(task, sequence, step)
        end.to raise_error(StandardError)

        # Step should maintain its state even after error
        expect(step.workflow_step_id).to be_present
        expect(step.task_id).to eq(task.task_id)
        step.reload
        expect(step).to be_persisted
      end
    end
  end

  describe 'framework handle() method coordination' do
    it 'places AutomaticEventPublishing before Base in the method lookup chain' do
      ancestors = described_class.ancestors

      auto_publishing_index = ancestors.index(Tasker::StepHandler::AutomaticEventPublishing)
      base_index = ancestors.index(described_class)

      expect(auto_publishing_index).to be < base_index
    end

    it 'coordinates between framework handle() and developer process() methods' do
      handler = TestStepHandler.new

      # The framework handle() method should coordinate with developer process() method
      expect(handler).to respond_to(:handle)
      expect(handler).to respond_to(:process)

      # Should not raise an error when framework calls developer method
      expect do
        handler.handle(task, sequence, step)
      end.not_to raise_error
    end
  end

  describe 'integration with real workflow data' do
    let(:handler) { TestStepHandler.new }

    before do
      allow(handler).to receive(:publish_step_started)
      allow(handler).to receive(:publish_step_completed)
      allow(handler).to receive(:publish_event)
    end

    it 'works with factory-created task and step data' do
      expect(task).to be_persisted
      expect(step).to be_persisted
      expect(step.task).to eq(task)

      handler.handle(task, sequence, step)

      # Verify events were published with real data
      expect(handler).to have_received(:publish_step_started).with(step)
      expect(handler).to have_received(:publish_step_completed).with(step)
    end

    it 'handles task context correctly' do
      handler.handle(task, sequence, step)

      # Verify the task has the context we set
      expect(task.context).to include('dummy' => true)
      expect(step.results).to include('test' => 'success')
    end
  end
end
