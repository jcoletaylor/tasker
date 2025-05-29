# frozen_string_literal: true

require 'rails_helper'
require_relative '../../dummy/app/tasks/custom_identity_strategy'

RSpec.describe CustomIdentityStrategy do
  include FactoryWorkflowHelpers

  before do
    # Register the handler for factory usage
    register_task_handler(DummyTask::TASK_REGISTRY_NAME, DummyTask)
  end

  let(:task) { create_dummy_task_workflow(context: { dummy: true }, reason: 'custom identity strategy test') }
  let(:identity_options) { task.send(:identity_options) }

  describe '#generate_identity_hash' do
    it 'generates a custom prefixed UUID' do
      strategy = described_class.new
      result = strategy.generate_identity_hash(task, identity_options)

      expect(result).to match(/^custom-task-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/)
    end
  end
end
