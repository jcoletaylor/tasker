# frozen_string_literal: true

require 'rails_helper'
require_relative '../../../examples/test_authenticator'

RSpec.describe Tasker::Authentication::Coordinator do
  let(:controller) { double('Controller') }

  # Isolate singleton state to prevent test pollution
  around do |example|
    original_config = Tasker::Configuration.instance_variable_get(:@configuration)
    # Reset the coordinator's cached authenticator before each test
    described_class.reset!
    # Reset test authenticator state
    TestAuthenticator.reset!

    example.run
  ensure
    # Restore original configuration and reset coordinator after each test
    Tasker::Configuration.instance_variable_set(:@configuration, original_config)
    described_class.reset!
    TestAuthenticator.reset!
  end

  describe '.authenticator' do
    context 'with authentication disabled' do
      before do
        Tasker.configuration.auth.authentication_enabled = false
      end

      it 'returns a NoneAuthenticator instance' do
        expect(described_class.authenticator).to be_a(Tasker::Authentication::NoneAuthenticator)
      end
    end

    context 'with custom authentication enabled' do
      before do
        Tasker.configuration.auth.authentication_enabled = true
        Tasker.configuration.auth.authenticator_class = 'TestAuthenticator'
      end

      it 'returns the custom authenticator instance' do
        expect(described_class.authenticator).to be_a(TestAuthenticator)
      end

      it 'passes options to the authenticator' do
        options = { key: 'value' }
        Tasker.configuration do |config|
          config.auth do |auth|
            auth.authentication_enabled = true
            auth.authenticator_class = 'TestAuthenticator'
            # Additional options can be passed through the configuration block
          end
        end
        described_class.reset!

        authenticator = described_class.authenticator
        expect(authenticator).to be_a(TestAuthenticator)
      end
    end

    context 'with authentication enabled but missing authenticator_class' do
      before do
        Tasker.configuration.auth.authentication_enabled = true
        Tasker.configuration.auth.authenticator_class = nil
      end

      it 'raises ConfigurationError' do
        expect { described_class.authenticator }.to raise_error(
          Tasker::Authentication::ConfigurationError,
          /Authentication is enabled but no authenticator_class is specified/
        )
      end
    end

    context 'with invalid authenticator class' do
      before do
        Tasker.configuration.auth.authentication_enabled = true
        Tasker.configuration.auth.authenticator_class = 'NonExistentClass'
      end

      it 'raises NameError' do
        expect { described_class.authenticator }.to raise_error(NameError)
      end
    end
  end

  describe 'interface validation' do
    let(:incomplete_authenticator_class) do
      Class.new do
        def initialize(options = {}); end
        # Missing authenticate! and current_user methods
      end
    end

    before do
      stub_const('IncompleteAuthenticator', incomplete_authenticator_class)
      Tasker.configuration.auth.authentication_enabled = true
      Tasker.configuration.auth.authenticator_class = 'IncompleteAuthenticator'
    end

    it 'raises InterfaceError for missing authenticate! method' do
      expect { described_class.authenticator }.to raise_error(
        Tasker::Authentication::InterfaceError,
        /must implement #authenticate!/
      )
    end
  end

  describe 'configuration validation' do
    before do
      TestAuthenticator.set_validation_errors(['Invalid configuration'])
      Tasker.configuration.auth.authentication_enabled = true
      Tasker.configuration.auth.authenticator_class = 'TestAuthenticator'
    end

    it 'raises ConfigurationError for validation failures' do
      expect { described_class.authenticator }.to raise_error(
        Tasker::Authentication::ConfigurationError,
        /Authenticator configuration errors: Invalid configuration/
      )
    end
  end

  describe 'method delegation' do
    before do
      Tasker.configuration.auth.authentication_enabled = true
      Tasker.configuration.auth.authenticator_class = 'TestAuthenticator'
    end

    describe '.authenticate!' do
      it 'delegates to authenticator' do
        expect(described_class.authenticator).to receive(:authenticate!).with(controller)
        described_class.authenticate!(controller)
      end
    end

    describe '.current_user' do
      it 'delegates to authenticator' do
        user = TestUser.new
        TestAuthenticator.set_current_user(user)

        expect(described_class.current_user(controller)).to eq(user)
      end
    end

    describe '.authenticated?' do
      it 'delegates to authenticator' do
        TestAuthenticator.set_current_user(TestUser.new)

        expect(described_class.authenticated?(controller)).to be true
      end
    end
  end

  describe '.reset!' do
    it 'clears the cached authenticator' do
      Tasker.configuration.auth.authentication_enabled = false
      first_authenticator = described_class.authenticator

      described_class.reset!
      second_authenticator = described_class.authenticator

      expect(first_authenticator).not_to be(second_authenticator)
    end
  end
end
