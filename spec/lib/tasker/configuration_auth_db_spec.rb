# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Configuration, 'Auth & Database Features' do
  let(:config) { described_class.new }

  # Store original configuration before tests
  around do |example|
    original_config = described_class.instance_variable_get(:@configuration)
    example.run
  ensure
    # Restore original configuration after each test
    described_class.instance_variable_set(:@configuration, original_config)
  end

  describe 'authentication configuration' do
    it 'has default authentication values' do
      expect(config.authentication_strategy).to eq(:none)
      expect(config.authentication_options).to eq({})
      expect(config.current_user_method).to eq(:current_user)
      expect(config.authenticate_user_method).to eq(:authenticate_user!)
    end

    it 'allows setting authentication strategy' do
      config.authentication_strategy = :devise
      expect(config.authentication_strategy).to eq(:devise)
    end

    it 'allows setting authentication options' do
      options = { scope: :user, failure_app: 'Devise::FailureApp' }
      config.authentication_options = options
      expect(config.authentication_options).to eq(options)
    end

    it 'allows setting current user method' do
      config.current_user_method = :current_api_user
      expect(config.current_user_method).to eq(:current_api_user)
    end

    it 'allows setting authenticate user method' do
      config.authenticate_user_method = :authenticate_api_user!
      expect(config.authenticate_user_method).to eq(:authenticate_api_user!)
    end

    context 'when configured for devise' do
      it 'can be configured with devise options' do
        config.authentication_strategy = :devise
        config.authentication_options = {
          scope: :user,
          failure_app: 'Devise::FailureApp'
        }

        expect(config.authentication_strategy).to eq(:devise)
        expect(config.authentication_options[:scope]).to eq(:user)
        expect(config.authentication_options[:failure_app]).to eq('Devise::FailureApp')
      end
    end

    context 'when configured for custom authentication' do
      it 'can be configured with custom options' do
        config.authentication_strategy = :custom
        config.authentication_options = {
          authenticator_class: 'MyApp::ApiAuthenticator',
          token_header: 'X-API-Token'
        }
        config.current_user_method = :current_api_user
        config.authenticate_user_method = :authenticate_api_user!

        expect(config.authentication_strategy).to eq(:custom)
        expect(config.authentication_options[:authenticator_class]).to eq('MyApp::ApiAuthenticator')
        expect(config.authentication_options[:token_header]).to eq('X-API-Token')
        expect(config.current_user_method).to eq(:current_api_user)
        expect(config.authenticate_user_method).to eq(:authenticate_api_user!)
      end
    end
  end

  describe 'authorization configuration' do
    it 'has default authorization values' do
      expect(config.authorization_coordinator_class).to eq('Tasker::Authorization::BaseCoordinator')
      expect(config.authorizable_user_class).to be_nil
      expect(config.enable_authorization).to be(false)
    end

    it 'allows setting authorization coordinator class' do
      config.authorization_coordinator_class = 'MyApp::AuthorizationCoordinator'
      expect(config.authorization_coordinator_class).to eq('MyApp::AuthorizationCoordinator')
    end

    it 'allows setting authorizable user class' do
      config.authorizable_user_class = 'User'
      expect(config.authorizable_user_class).to eq('User')
    end

    it 'allows enabling authorization' do
      config.enable_authorization = true
      expect(config.enable_authorization).to be(true)
    end

    context 'when fully configured for authorization' do
      it 'can be configured with all authorization options' do
        config.enable_authorization = true
        config.authorization_coordinator_class = 'MyApp::AuthorizationCoordinator'
        config.authorizable_user_class = 'User'

        expect(config.enable_authorization).to be(true)
        expect(config.authorization_coordinator_class).to eq('MyApp::AuthorizationCoordinator')
        expect(config.authorizable_user_class).to eq('User')
      end
    end
  end

  describe 'database configuration' do
    it 'has default database values' do
      expect(config.database_name).to be_nil
      expect(config.enable_secondary_database).to be(false)
    end

    it 'allows setting database name as string' do
      config.database_name = 'tasker'
      expect(config.database_name).to eq('tasker')
    end

    it 'allows setting database name as symbol' do
      config.database_name = :tasker
      expect(config.database_name).to eq(:tasker)
    end

    it 'allows enabling secondary database' do
      config.enable_secondary_database = true
      expect(config.enable_secondary_database).to be(true)
    end

    context 'when configured for secondary database' do
      it 'can be configured with named database' do
        config.enable_secondary_database = true
        config.database_name = :tasker

        expect(config.enable_secondary_database).to be(true)
        expect(config.database_name).to eq(:tasker)
      end

      it 'supports string database names' do
        config.enable_secondary_database = true
        config.database_name = 'tasker_production'

        expect(config.enable_secondary_database).to be(true)
        expect(config.database_name).to eq('tasker_production')
      end
    end
  end

  describe 'integrated configuration' do
    it 'supports configuring all features together' do
      # Authentication
      config.authentication_strategy = :devise
      config.authentication_options = { scope: :user }

      # Authorization
      config.enable_authorization = true
      config.authorization_coordinator_class = 'MyApp::AuthorizationCoordinator'
      config.authorizable_user_class = 'User'

      # Database
      config.enable_secondary_database = true
      config.database_name = :tasker

      # Verify all settings
      expect(config.authentication_strategy).to eq(:devise)
      expect(config.authentication_options[:scope]).to eq(:user)
      expect(config.enable_authorization).to be(true)
      expect(config.authorization_coordinator_class).to eq('MyApp::AuthorizationCoordinator')
      expect(config.authorizable_user_class).to eq('User')
      expect(config.enable_secondary_database).to be(true)
      expect(config.database_name).to eq(:tasker)
    end
  end

  describe 'global configuration' do
    it 'allows block configuration with new attributes' do
      # Use a fresh configuration instance to avoid singleton pollution
      config_instance = described_class.new
      allow(described_class).to receive(:configuration).and_yield(config_instance).and_return(config_instance)

      Tasker.configuration do |config|
        config.authentication_strategy = :devise
        config.enable_authorization = true
        config.enable_secondary_database = true
      end

      expect(config_instance.authentication_strategy).to eq(:devise)
      expect(config_instance.enable_authorization).to be(true)
      expect(config_instance.enable_secondary_database).to be(true)
    end
  end
end
