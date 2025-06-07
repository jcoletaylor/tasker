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
        auth.strategy = :devise
      end

      expect(result).to be_a(Tasker::Configuration::AuthConfiguration)
      expect(result.strategy).to eq(:devise)
    end
  end

  describe 'authentication configuration' do
    it 'has default authentication values' do
      auth = config.auth
      expect(auth.strategy).to eq(:none)
      expect(auth.options).to eq({})
      expect(auth.current_user_method).to eq(:current_user)
      expect(auth.authenticate_user_method).to eq(:authenticate_user!)
    end

    it 'allows setting authentication strategy and options' do
      config.auth do |auth|
        auth.strategy = :devise
        auth.options = { scope: :user }
      end

      expect(config.auth.strategy).to eq(:devise)
      expect(config.auth.options[:scope]).to eq(:user)
    end

    it 'supports different authentication strategies' do
      config.auth.strategy = :custom
      expect(config.auth.strategy).to eq(:custom)

      config.auth.strategy = :none
      expect(config.auth.strategy).to eq(:none)
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
      expect(auth.coordinator_class).to eq('Tasker::Authorization::BaseCoordinator')
      expect(auth.user_class).to be_nil
      expect(auth.enabled).to be(false)
    end

    it 'allows setting authorization options' do
      config.auth do |auth|
        auth.coordinator_class = 'MyApp::AuthorizationCoordinator'
        auth.user_class = 'User'
        auth.enabled = true
      end

      expect(config.auth.coordinator_class).to eq('MyApp::AuthorizationCoordinator')
      expect(config.auth.user_class).to eq('User')
      expect(config.auth.enabled).to be(true)
    end
  end

  describe 'global configuration integration' do
    it 'works with Tasker.configuration' do
      Tasker.configuration do |config|
        config.auth do |auth|
          auth.strategy = :devise
          auth.enabled = true
        end
      end

      expect(Tasker.configuration.auth.strategy).to eq(:devise)
      expect(Tasker.configuration.auth.enabled).to be(true)
    end
  end

  describe 'integration scenarios' do
    context 'Devise integration' do
      it 'configures for typical Devise setup' do
        config.auth do |auth|
          auth.strategy = :devise
          auth.options = { scope: :user, failure_app: 'Devise::FailureApp' }
          auth.current_user_method = :current_user
          auth.authenticate_user_method = :authenticate_user!
          auth.enabled = true
        end

        expect(config.auth.strategy).to eq(:devise)
        expect(config.auth.options[:scope]).to eq(:user)
        expect(config.auth.options[:failure_app]).to eq('Devise::FailureApp')
        expect(config.auth.enabled).to be(true)
      end
    end

    context 'API authentication' do
      it 'configures for API token authentication' do
        config.auth do |auth|
          auth.strategy = :custom
          auth.options = { authenticator_class: 'MyApp::ApiAuthenticator' }
          auth.current_user_method = :current_api_user
          auth.authenticate_user_method = :authenticate_api_user!
          auth.enabled = false
        end

        expect(config.auth.strategy).to eq(:custom)
        expect(config.auth.options[:authenticator_class]).to eq('MyApp::ApiAuthenticator')
        expect(config.auth.current_user_method).to eq(:current_api_user)
      end
    end

    context 'No authentication' do
      it 'configures for development/testing with no auth' do
        config.auth do |auth|
          auth.strategy = :none
          auth.enabled = false
        end

        expect(config.auth.strategy).to eq(:none)
        expect(config.auth.enabled).to be(false)
      end
    end
  end
end
