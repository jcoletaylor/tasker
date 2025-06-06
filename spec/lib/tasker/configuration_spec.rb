# frozen_string_literal: true

require 'rails_helper'
require_relative '../../dummy/app/tasks/custom_identity_strategy'

RSpec.describe Tasker::Configuration do
  before do
    # Reset to default configuration before each test
    Tasker.reset_configuration!
  end

  describe '#identity_strategy_instance' do
    it 'returns a default IdentityStrategy when identity_strategy is :default' do
      config = described_class.new
      config.identity_strategy = :default

      strategy = config.identity_strategy_instance

      expect(strategy).to be_a(Tasker::IdentityStrategy)
      expect(strategy).not_to be_a(Tasker::HashIdentityStrategy)
    end

    it 'returns a HashIdentityStrategy when identity_strategy is :hash' do
      config = described_class.new
      config.identity_strategy = :hash

      strategy = config.identity_strategy_instance

      expect(strategy).to be_a(Tasker::HashIdentityStrategy)
    end

    it 'returns a custom strategy when identity_strategy is :custom' do
      config = described_class.new
      config.identity_strategy = :custom
      config.identity_strategy_class = 'CustomIdentityStrategy'

      strategy = config.identity_strategy_instance

      expect(strategy).to be_a(CustomIdentityStrategy)
    end

    it 'raises an error when :custom is selected but no class is provided' do
      config = described_class.new
      config.identity_strategy = :custom
      config.identity_strategy_class = nil

      expect { config.identity_strategy_instance }.to raise_error(ArgumentError, /no identity_strategy_class provided/)
    end

    it 'raises an error when :custom is selected with an invalid class name' do
      config = described_class.new
      config.identity_strategy = :custom
      config.identity_strategy_class = 'NonExistentClass'

      expect { config.identity_strategy_instance }.to raise_error(ArgumentError, /Invalid identity_strategy_class/)
    end

    it 'raises an error for an unknown strategy type' do
      config = described_class.new
      config.identity_strategy = :unknown

      expect { config.identity_strategy_instance }.to raise_error(ArgumentError, /Unknown identity_strategy/)
    end
  end

  describe 'Tasker.configuration' do
    it 'allows setting identity_strategy through the block syntax' do
      original_strategy = Tasker.configuration.identity_strategy

      begin
        Tasker.configuration do |config|
          config.identity_strategy = :hash
          expect(Tasker.configuration.identity_strategy).to eq(:hash)
          expect(Tasker.configuration.identity_strategy_instance).to be_a(Tasker::HashIdentityStrategy)
        end
      rescue StandardError => e
        Rails.logger.error("Error setting identity strategy: #{e.message}")
        raise e
      ensure
        # Only restore the strategy setting - identity_strategy_instance is computed
        Tasker.configuration.identity_strategy = original_strategy
      end
    end
  end
end
