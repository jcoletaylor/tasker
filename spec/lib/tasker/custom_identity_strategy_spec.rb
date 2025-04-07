# frozen_string_literal: true

require 'rails_helper'
require_relative '../../dummy/app/tasks/custom_identity_strategy'

RSpec.describe CustomIdentityStrategy do
  let(:task_request) { Tasker::Types::TaskRequest.new(name: 'dummy_action', context: { dummy: true }) }
  let(:task)         { Tasker::Task.create_with_defaults!(task_request) }
  let(:identity_options) { task.send(:identity_options) }

  describe '#generate_identity_hash' do
    it 'generates a custom prefixed UUID' do
      strategy = described_class.new
      result = strategy.generate_identity_hash(task, identity_options)

      expect(result).to match(/^custom-task-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/)
    end
  end
end
