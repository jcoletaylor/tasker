# frozen_string_literal: true

require 'rails_helper'
require_relative '../../dummy/app/tasks/custom_identity_strategy'

RSpec.describe Tasker::Configuration do
  let(:config) { described_class.new }

  before do
    # Reset to default configuration before each test
    Tasker.reset_configuration!
  end

  describe '#identity_strategy_instance' do
    it 'returns a default IdentityStrategy when identity_strategy is :default' do
      # Store original configuration to restore later
      original_strategy = Tasker.configuration.engine.identity_strategy

      # Test setting and getting the identity strategy
      config.engine.identity_strategy = :default

      # Check the updated strategy and its instance
      expect(config.engine.identity_strategy).to eq(:default)
      expect(config.engine.identity_strategy_instance).to be_a(Tasker::IdentityStrategy)

      # Restore original configuration
      Tasker.configuration.engine.identity_strategy = original_strategy
    end

    it 'returns a HashIdentityStrategy when identity_strategy is :hash' do
      config.engine.identity_strategy = :hash

      expect(config.engine.identity_strategy).to eq(:hash)
      expect(config.engine.identity_strategy_instance).to be_a(Tasker::HashIdentityStrategy)
    end

    it 'returns a custom strategy when identity_strategy is :custom' do
      config.engine.identity_strategy = :custom
      config.engine.identity_strategy_class = 'Tasker::HashIdentityStrategy'

      expect(config.engine.identity_strategy).to eq(:custom)
      expect(config.engine.identity_strategy_instance).to be_a(Tasker::HashIdentityStrategy)
    end

    it 'raises an error when :custom is selected but no class is provided' do
      config.engine.identity_strategy = :custom

      expect do
        config.engine.identity_strategy_instance
      end.to raise_error(ArgumentError,
                         /Custom identity strategy selected but no identity_strategy_class provided/)
    end

    it 'raises an error when :custom is selected with an invalid class name' do
      config.engine.identity_strategy = :custom
      config.engine.identity_strategy_class = 'NonExistentClass'

      expect do
        config.engine.identity_strategy_instance
      end.to raise_error(ArgumentError, /Invalid identity_strategy_class/)
    end

    it 'raises an error for an unknown strategy type' do
      config.engine.identity_strategy = :unknown

      expect { config.engine.identity_strategy_instance }.to raise_error(ArgumentError, /Unknown identity_strategy/)
    end
  end

  describe 'Tasker.configuration' do
    it 'allows setting identity_strategy through the block syntax' do
      # Store original configuration to restore later
      original_strategy = Tasker.configuration.engine.identity_strategy

      # Test setting and getting the identity strategy
      Tasker.configuration do |config|
        config.engine.identity_strategy = :hash
      end

      # Check the updated strategy and its instance
      expect(Tasker.configuration.engine.identity_strategy).to eq(:hash)
      expect(Tasker.configuration.engine.identity_strategy_instance).to be_a(Tasker::HashIdentityStrategy)

      # Restore original configuration
      Tasker.configuration.engine.identity_strategy = original_strategy
    end
  end

  describe 'database configuration' do
    it 'has default database configuration values' do
      expect(config.database.name).to be_nil
      expect(config.database.enable_secondary_database).to be false
    end

    it 'allows setting database configuration' do
      config.database do |db|
        db.name = :tasker
        db.enable_secondary_database = true
      end

      expect(config.database.name).to eq(:tasker)
      expect(config.database.enable_secondary_database).to be true
    end

    it 'supports string database names' do
      config.database do |db|
        db.name = 'tasker_production'
        db.enable_secondary_database = true
      end

      expect(config.database.name).to eq('tasker_production')
    end
  end
end
