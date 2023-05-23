# typed: false
# frozen_string_literal: true

require 'rails_helper'
require_relative '../../helpers/task_helpers'
require_relative '../../mocks/dummy_task'

module Tasker
  RSpec.describe TaskRunnerJob do
    context 'perform a task runner job' do
      let(:helper)       { Helpers::TaskHelpers.new                                                               }
      let(:task_handler) { helper.factory.get(DummyTask::TASK_REGISTRY_NAME)                                      }
      let(:task_request) { Tasker::TaskRequest.new(name: DummyTask::TASK_REGISTRY_NAME, context: { dummy: true }) }
      let(:task)         { task_handler.initialize_task!(task_request)                                            }

      before(:all) do
        DependentSystem.find_or_create_by!(name: Helpers::TaskHelpers::DEPENDENT_SYSTEM)
      end

      it 'is able to perform a task job' do
        runner = described_class.new
        runner.perform(task.task_id)
        task.reload
        expect(task.status).to eq(Tasker::Constants::TaskStatuses::COMPLETE)
      end
    end
  end
end
