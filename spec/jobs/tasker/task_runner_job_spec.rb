# typed: false
# frozen_string_literal: true

require 'rails_helper'
require_relative '../../mocks/dummy_task'

module Tasker
  RSpec.describe(TaskRunnerJob) do
    before do
      # Register the handler for factory usage
      register_task_handler(DummyTask::TASK_REGISTRY_NAME, DummyTask)
    end

    context 'when performing a task runner job' do
      it 'is able to perform a task job' do
        # Create task using factory approach
        task = create_dummy_task_workflow(context: { dummy: true }, reason: 'job runner test')

        runner = described_class.new
        runner.perform(task.id)
        task.reload
        expect(task.status).to(eq(Tasker::Constants::TaskStatuses::COMPLETE))
      end
    end
  end
end
