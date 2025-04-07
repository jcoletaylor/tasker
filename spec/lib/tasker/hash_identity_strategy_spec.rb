# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::HashIdentityStrategy do
  let(:task_request) { Tasker::Types::TaskRequest.new(name: 'dummy_action', context: { dummy: true }) }
  let(:task)         { Tasker::Task.create_with_defaults!(task_request) }
  let(:identity_options) { task.send(:identity_options) }

  describe '#generate_identity_hash' do
    it 'generates a SHA256 hash of the identity options' do
      strategy = described_class.new
      result = strategy.generate_identity_hash(task, identity_options)
      expected = Digest::SHA256.hexdigest(identity_options.to_json)

      expect(result).to eq(expected)
      expect(result).to match(/^[0-9a-f]{64}$/)
    end

    it 'generates different hashes for different options' do
      strategy = described_class.new
      result1 = strategy.generate_identity_hash(task, identity_options)

      # Change one value in the options
      different_options = identity_options.merge(initiator: 'different_user')
      result2 = strategy.generate_identity_hash(task, different_options)

      expect(result1).not_to eq(result2)
    end
  end
end
