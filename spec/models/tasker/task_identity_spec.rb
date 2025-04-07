# frozen_string_literal: true

require 'rails_helper'
require_relative '../../dummy/app/tasks/custom_identity_strategy'

RSpec.describe Tasker::Task, '#set_identity_hash' do
  before do
    # Reset configuration before each test
    Tasker.reset_configuration!
  end

  let(:task_request) { Tasker::Types::TaskRequest.new(name: 'dummy_action', context: { dummy: true }) }
  let(:task)         { described_class.create_with_defaults!(task_request)             }

  context 'with default strategy' do
    before do
      Tasker.configuration.identity_strategy = :default
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
      Tasker.configuration.identity_strategy = :hash
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
      Tasker.configuration.identity_strategy = :custom
      Tasker.configuration.identity_strategy_class = 'CustomIdentityStrategy'
    end

    it 'uses the custom strategy to generate the identity_hash' do
      expect(task.identity_hash).to match(/^custom-task-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/)
    end
  end
end
