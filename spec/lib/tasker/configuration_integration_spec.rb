# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Tasker Configuration Integration' do
  # Isolate singleton state
  around do |example|
    original_config = Tasker::Configuration.instance_variable_get(:@configuration)
    example.run
  ensure
    Tasker::Configuration.instance_variable_set(:@configuration, original_config)
  end

  describe 'Devise integration configuration' do
    it 'configures authentication and authorization for Devise' do
      # Create a fresh config instance to avoid singleton pollution
      config_instance = Tasker::Configuration.new
      allow(Tasker::Configuration).to receive(:configuration).and_yield(config_instance).and_return(config_instance)

      # Configure like a real application would
      Tasker.configuration do |config|
        config.authentication_strategy = :devise
        config.authentication_options = {
          scope: :user,
          failure_app: 'Devise::FailureApp'
        }
        config.enable_authorization = true
        config.authorization_coordinator_class = 'CustomAuthorizationCoordinator'
        config.authorizable_user_class = 'User'
      end

      # Verify the configuration is set up correctly
      expect(config_instance.authentication_strategy).to eq(:devise)
      expect(config_instance.authentication_options[:scope]).to eq(:user)
      expect(config_instance.authentication_options[:failure_app]).to eq('Devise::FailureApp')
      expect(config_instance.enable_authorization).to be(true)
      expect(config_instance.authorization_coordinator_class).to eq('CustomAuthorizationCoordinator')
      expect(config_instance.authorizable_user_class).to eq('User')
    end
  end

  describe 'API authentication configuration' do
    it 'configures authentication for API-based systems' do
      config_instance = Tasker::Configuration.new
      allow(Tasker::Configuration).to receive(:configuration).and_yield(config_instance).and_return(config_instance)

      Tasker.configuration do |config|
        config.authentication_strategy = :custom
        config.authentication_options = {
          authenticator_class: 'ApiAuthenticator',
          token_header: 'X-API-Token'
        }
        config.current_user_method = :current_api_user
        config.authenticate_user_method = :authenticate_api_user!
        config.enable_authorization = true
      end

      expect(config_instance.authentication_strategy).to eq(:custom)
      expect(config_instance.authentication_options[:authenticator_class]).to eq('ApiAuthenticator')
      expect(config_instance.authentication_options[:token_header]).to eq('X-API-Token')
      expect(config_instance.current_user_method).to eq(:current_api_user)
      expect(config_instance.authenticate_user_method).to eq(:authenticate_api_user!)
      expect(config_instance.enable_authorization).to be(true)
    end
  end

  describe 'Multi-database configuration' do
    it 'configures secondary database using Rails database.yml references' do
      config_instance = Tasker::Configuration.new
      allow(Tasker::Configuration).to receive(:configuration).and_yield(config_instance).and_return(config_instance)

      Tasker.configuration do |config|
        config.enable_secondary_database = true
        config.database_name = :tasker # References database.yml configuration
      end

      expect(config_instance.enable_secondary_database).to be(true)
      expect(config_instance.database_name).to eq(:tasker)
    end

    it 'supports string database names' do
      config_instance = Tasker::Configuration.new
      allow(Tasker::Configuration).to receive(:configuration).and_yield(config_instance).and_return(config_instance)

      Tasker.configuration do |config|
        config.enable_secondary_database = true
        config.database_name = 'tasker_production'
      end

      expect(config_instance.enable_secondary_database).to be(true)
      expect(config_instance.database_name).to eq('tasker_production')
    end
  end

  describe 'No authentication configuration' do
    it 'maintains backward compatibility with no authentication' do
      config_instance = Tasker::Configuration.new
      allow(Tasker::Configuration).to receive(:configuration).and_yield(config_instance).and_return(config_instance)

      # Don't configure authentication - should default to :none
      Tasker.configuration do |config|
        # Other configurations that don't affect auth
        config.task_handler_directory = 'my_tasks'
      end

      expect(config_instance.authentication_strategy).to eq(:none)
      expect(config_instance.enable_authorization).to be(false)
      expect(config_instance.enable_secondary_database).to be(false)
      expect(config_instance.task_handler_directory).to eq('my_tasks')
    end
  end

  describe 'Full-featured configuration' do
    it 'supports configuring all features together' do
      config_instance = Tasker::Configuration.new
      allow(Tasker::Configuration).to receive(:configuration).and_yield(config_instance).and_return(config_instance)

      Tasker.configuration do |config|
        # Authentication
        config.authentication_strategy = :devise
        config.authentication_options = { scope: :admin }

        # Authorization
        config.enable_authorization = true
        config.authorization_coordinator_class = 'MyApp::TaskerAuthorizationCoordinator'
        config.authorizable_user_class = 'AdminUser'

        # Database
        config.enable_secondary_database = true
        config.database_name = :tasker_production

        # Existing configuration
        config.task_handler_directory = 'workflows'
        config.enable_telemetry = false
      end

      # Verify all settings are preserved
      expect(config_instance.authentication_strategy).to eq(:devise)
      expect(config_instance.authentication_options[:scope]).to eq(:admin)
      expect(config_instance.enable_authorization).to be(true)
      expect(config_instance.authorization_coordinator_class).to eq('MyApp::TaskerAuthorizationCoordinator')
      expect(config_instance.authorizable_user_class).to eq('AdminUser')
      expect(config_instance.enable_secondary_database).to be(true)
      expect(config_instance.database_name).to eq(:tasker_production)
      expect(config_instance.task_handler_directory).to eq('workflows')
      expect(config_instance.enable_telemetry).to be(false)
    end
  end

  describe 'configuration validation scenarios' do
    it 'allows authorization without authentication' do
      config_instance = Tasker::Configuration.new
      allow(Tasker::Configuration).to receive(:configuration).and_yield(config_instance).and_return(config_instance)

      Tasker.configuration do |config|
        config.authentication_strategy = :none
        config.enable_authorization = true # This should be allowed
        config.authorization_coordinator_class = 'PublicResourceCoordinator'
      end

      expect(config_instance.authentication_strategy).to eq(:none)
      expect(config_instance.enable_authorization).to be(true)
      expect(config_instance.authorization_coordinator_class).to eq('PublicResourceCoordinator')
    end

    it 'allows database configuration without authentication' do
      config_instance = Tasker::Configuration.new
      allow(Tasker::Configuration).to receive(:configuration).and_yield(config_instance).and_return(config_instance)

      Tasker.configuration do |config|
        config.authentication_strategy = :none
        config.enable_secondary_database = true
        config.database_name = :tasker_analytics
      end

      expect(config_instance.authentication_strategy).to eq(:none)
      expect(config_instance.enable_secondary_database).to be(true)
      expect(config_instance.database_name).to eq(:tasker_analytics)
    end
  end
end
