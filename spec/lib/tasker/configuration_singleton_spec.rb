# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Configuration, 'Singleton Behavior' do
  # Properly isolate singleton state between tests
  before do
    @original_config = described_class.instance_variable_get(:@configuration)
    described_class.instance_variable_set(:@configuration, nil)
  end

  after do
    described_class.instance_variable_set(:@configuration, @original_config)
  end

  describe '.configuration' do
    it 'returns a singleton instance' do
      config1 = described_class.configuration
      config2 = described_class.configuration

      expect(config1).to be_a(described_class)
      expect(config1).to be(config2) # Same object reference
    end

    it 'yields the configuration instance when block given' do
      yielded_config = nil
      returned_config = described_class.configuration do |config|
        yielded_config = config
      end

      expect(yielded_config).to be_a(described_class)
      expect(yielded_config).to be(returned_config)
    end

    it 'allows configuration via block' do
      described_class.configuration do |config|
        config.auth do |auth|
          auth.authentication_enabled = true
          auth.authenticator_class = 'DeviseAuthenticator'
          auth.authorization_enabled = true
        end

        config.database do |db|
          db.name = :tasker
        end
      end

      config = described_class.configuration
      expect(config.auth.authentication_enabled).to be(true)
      expect(config.auth.authenticator_class).to eq('DeviseAuthenticator')
      expect(config.auth.authorization_enabled).to be(true)
      expect(config.database.name).to eq(:tasker)
    end
  end

  describe '.reset_configuration!' do
    it 'creates a new configuration instance' do
      # Set some values on the current config
      described_class.configuration do |config|
        config.auth do |auth|
          auth.authentication_enabled = true
          auth.authenticator_class = 'DeviseAuthenticator'
          auth.authorization_enabled = true
        end
      end

      old_config = described_class.configuration

      # Reset and verify it's a new instance with defaults
      new_config = described_class.reset_configuration!

      expect(new_config).to be_a(described_class)
      expect(new_config).not_to be(old_config)
      expect(new_config.auth.authentication_enabled).to be(false) # default value
      expect(new_config.auth.authorization_enabled).to be(false) # default value
    end
  end

  describe 'Tasker.configuration delegation' do
    it 'delegates to Configuration.configuration' do
      expect(described_class).to receive(:configuration).and_call_original
      Tasker.configuration
    end

    it 'passes block to Configuration.configuration' do
      block_called = false
      config_received = nil

      Tasker.configuration do |config|
        block_called = true
        config_received = config
      end

      expect(block_called).to be(true)
      expect(config_received).to be_a(described_class)
    end
  end
end
