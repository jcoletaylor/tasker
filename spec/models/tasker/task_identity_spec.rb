# frozen_string_literal: true

require 'rails_helper'
require_relative '../../dummy/app/tasks/custom_identity_strategy'

RSpec.describe Tasker::Task, '#set_identity_hash' do
  include FactoryWorkflowHelpers

  before do
    # Reset configuration before each test
    Tasker.reset_configuration!

    # Register the handler for factory usage
    register_task_handler(DummyTask::TASK_REGISTRY_NAME, DummyTask)
  end

  let(:task) { create_dummy_task_workflow(context: { dummy: true }, reason: 'task identity test') }

  context 'with default strategy' do
    before do
      Tasker.configuration do |config|
        config.engine do |engine|
          engine.identity_strategy = :default
        end
      end
    end

    it 'sets a UUID as the identity_hash' do
      expect(task.identity_hash).to match(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/)
    end

    it 'generates different hashes for identical tasks' do
      task.send(:set_identity_hash)
      hash1 = task.identity_hash

      task.identity_hash = nil
      task.send(:set_identity_hash)
      hash2 = task.identity_hash

      expect(hash1).not_to eq(hash2)
    end
  end

  context 'with hash strategy' do
    before do
      Tasker.configuration do |config|
        config.engine do |engine|
          engine.identity_strategy = :hash
        end
      end
    end

    it 'sets a SHA256 hash as the identity_hash' do
      expect(task.identity_hash).to match(/^[0-9a-f]{64}$/)
    end

    it 'generates identical hashes for identical tasks' do
      task.send(:set_identity_hash)
      hash1 = task.identity_hash

      task.identity_hash = nil
      task.send(:set_identity_hash)
      hash2 = task.identity_hash

      expect(hash1).to eq(hash2)
    end

    it 'generates different hashes for tasks with different attributes' do
      task.send(:set_identity_hash)
      hash1 = task.identity_hash

      task.initiator = 'different_user'
      task.identity_hash = nil
      task.send(:set_identity_hash)
      hash2 = task.identity_hash

      expect(hash1).not_to eq(hash2)
    end
  end

  context 'with custom strategy' do
    before do
      Tasker.configuration do |config|
        config.engine do |engine|
          engine.identity_strategy = :custom
          engine.identity_strategy_class = 'CustomIdentityStrategy'
        end
      end
    end

    it 'uses the custom strategy to generate the identity_hash' do
      expect(task.identity_hash).to match(/^custom-task-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/)
    end
  end
end
