# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Configuration, 'Auth Configuration' do
  let(:config) { described_class.new }

  # Store original configuration before tests
  around do |example|
    original_config = described_class.instance_variable_get(:@configuration)
    example.run
  ensure
    # Restore original configuration after each test
    described_class.instance_variable_set(:@configuration, original_config)
  end

  describe 'nested auth configuration' do
    it 'provides access to auth configuration block' do
      expect(config.auth).to be_a(Tasker::Configuration::AuthConfiguration)
    end

    it 'yields auth configuration in block' do
      expect { |b| config.auth(&b) }.to yield_with_args(Tasker::Configuration::AuthConfiguration)
    end

    it 'supports method chaining' do
      result = config.auth do |auth|
        auth.authentication_enabled = true
        auth.authenticator_class = 'DeviseAuthenticator'
      end

      expect(result).to be_a(Tasker::Configuration::AuthConfiguration)
      expect(result.authentication_enabled).to be(true)
      expect(result.authenticator_class).to eq('DeviseAuthenticator')
    end
  end

  describe 'authentication configuration' do
    it 'has default authentication values' do
      auth = config.auth
      expect(auth.authentication_enabled).to be(false)
      expect(auth.authenticator_class).to be_nil
      expect(auth.current_user_method).to eq(:current_user)
      expect(auth.authenticate_user_method).to eq(:authenticate_user!)
    end

    it 'allows setting authentication options' do
      config.auth do |auth|
        auth.authentication_enabled = true
        auth.authenticator_class = 'DeviseAuthenticator'
      end

      expect(config.auth.authentication_enabled).to be(true)
      expect(config.auth.authenticator_class).to eq('DeviseAuthenticator')
    end

    it 'supports enabling and disabling authentication' do
      config.auth.authentication_enabled = true
      expect(config.auth.authentication_enabled).to be(true)

      config.auth.authentication_enabled = false
      expect(config.auth.authentication_enabled).to be(false)
    end

    it 'allows setting custom user methods' do
      config.auth do |auth|
        auth.current_user_method = :current_api_user
        auth.authenticate_user_method = :authenticate_api_user!
      end

      expect(config.auth.current_user_method).to eq(:current_api_user)
      expect(config.auth.authenticate_user_method).to eq(:authenticate_api_user!)
    end
  end

  describe 'authorization configuration' do
    it 'has default authorization values' do
      auth = config.auth
      expect(auth.authorization_coordinator_class).to eq('Tasker::Authorization::BaseCoordinator')
      expect(auth.user_class).to be_nil
      expect(auth.authorization_enabled).to be(false)
    end

    it 'allows setting authorization options' do
      config.auth do |auth|
        auth.authorization_coordinator_class = 'MyApp::AuthorizationCoordinator'
        auth.user_class = 'User'
        auth.authorization_enabled = true
      end

      expect(config.auth.authorization_coordinator_class).to eq('MyApp::AuthorizationCoordinator')
      expect(config.auth.user_class).to eq('User')
      expect(config.auth.authorization_enabled).to be(true)
    end
  end

  describe 'global configuration integration' do
    it 'works with Tasker.configuration' do
      Tasker.configuration do |config|
        config.auth do |auth|
          auth.authentication_enabled = true
          auth.authenticator_class = 'DeviseAuthenticator'
          auth.authorization_enabled = true
        end
      end

      expect(Tasker.configuration.auth.authentication_enabled).to be(true)
      expect(Tasker.configuration.auth.authenticator_class).to eq('DeviseAuthenticator')
      expect(Tasker.configuration.auth.authorization_enabled).to be(true)
    end
  end

  describe 'integration scenarios' do
    context 'Devise integration' do
      it 'configures for typical Devise setup' do
        config.auth do |auth|
          auth.authentication_enabled = true
          auth.authenticator_class = 'DeviseAuthenticator'
          auth.current_user_method = :current_user
          auth.authenticate_user_method = :authenticate_user!
          auth.authorization_enabled = true
          auth.authorization_coordinator_class = 'MyApp::AuthorizationCoordinator'
        end

        expect(config.auth.authentication_enabled).to be(true)
        expect(config.auth.authenticator_class).to eq('DeviseAuthenticator')
        expect(config.auth.authorization_enabled).to be(true)
        expect(config.auth.authorization_coordinator_class).to eq('MyApp::AuthorizationCoordinator')
      end
    end

    context 'API authentication' do
      it 'configures for API token authentication' do
        config.auth do |auth|
          auth.authentication_enabled = true
          auth.authenticator_class = 'MyApp::ApiAuthenticator'
          auth.current_user_method = :current_api_user
          auth.authenticate_user_method = :authenticate_api_user!
          auth.authorization_enabled = false
        end

        expect(config.auth.authentication_enabled).to be(true)
        expect(config.auth.authenticator_class).to eq('MyApp::ApiAuthenticator')
        expect(config.auth.current_user_method).to eq(:current_api_user)
        expect(config.auth.authorization_enabled).to be(false)
      end
    end

    context 'No authentication' do
      it 'configures for development/testing with no auth' do
        config.auth do |auth|
          auth.authentication_enabled = false
          auth.authorization_enabled = false
        end

        expect(config.auth.authentication_enabled).to be(false)
        expect(config.auth.authorization_enabled).to be(false)
      end
    end
  end
end
