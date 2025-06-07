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
        config.auth do |auth|
          auth.strategy = :devise
          auth.options = {
            scope: :user,
            failure_app: 'Devise::FailureApp'
          }
          auth.enabled = true
          auth.coordinator_class = 'CustomAuthorizationCoordinator'
          auth.user_class = 'User'
        end

        config.database do |db|
          db.enable_secondary_database = true
          db.name = :tasker_users
        end

        config.telemetry do |tel|
          tel.service_name = 'tasker-devise-app'
          tel.configure_telemetry(batch_events: true)
        end

        config.engine do |engine|
          engine.task_handler_directory = 'user_tasks'
        end
      end

      # Verify the configuration is set up correctly
      expect(config_instance.auth.strategy).to eq(:devise)
      expect(config_instance.auth.options[:scope]).to eq(:user)
      expect(config_instance.auth.options[:failure_app]).to eq('Devise::FailureApp')
      expect(config_instance.auth.enabled).to be(true)
      expect(config_instance.auth.coordinator_class).to eq('CustomAuthorizationCoordinator')
      expect(config_instance.auth.user_class).to eq('User')

      expect(config_instance.database.enable_secondary_database).to be(true)
      expect(config_instance.database.name).to eq(:tasker_users)

      expect(config_instance.telemetry.service_name).to eq('tasker-devise-app')
      expect(config_instance.telemetry.config[:batch_events]).to be(true)

      expect(config_instance.engine.task_handler_directory).to eq('user_tasks')
    end
  end

  describe 'API authentication configuration' do
    it 'configures authentication for API-based systems' do
      config_instance = Tasker::Configuration.new
      allow(Tasker::Configuration).to receive(:configuration).and_yield(config_instance).and_return(config_instance)

      Tasker.configuration do |config|
        config.auth do |auth|
          auth.strategy = :custom
          auth.options = {
            authenticator_class: 'ApiAuthenticator',
            token_header: 'X-API-Token'
          }
          auth.current_user_method = :current_api_user
          auth.authenticate_user_method = :authenticate_api_user!
          auth.enabled = true
        end

        config.database do |db|
          db.enable_secondary_database = true
          db.name = 'tasker_api'
        end

        config.telemetry do |tel|
          tel.service_name = 'tasker-api'
          tel.filter_parameters = %i[api_key token]
        end

        config.engine do |engine|
          engine.task_handler_directory = 'api_tasks'
          engine.identity_strategy = :hash
        end
      end

      expect(config_instance.auth.strategy).to eq(:custom)
      expect(config_instance.auth.options[:authenticator_class]).to eq('ApiAuthenticator')
      expect(config_instance.auth.options[:token_header]).to eq('X-API-Token')
      expect(config_instance.auth.current_user_method).to eq(:current_api_user)
      expect(config_instance.auth.authenticate_user_method).to eq(:authenticate_api_user!)
      expect(config_instance.auth.enabled).to be(true)

      expect(config_instance.database.enable_secondary_database).to be(true)
      expect(config_instance.database.name).to eq('tasker_api')

      expect(config_instance.telemetry.service_name).to eq('tasker-api')
      expect(config_instance.telemetry.filter_parameters).to include(:api_key, :token)

      expect(config_instance.engine.task_handler_directory).to eq('api_tasks')
      expect(config_instance.engine.identity_strategy).to eq(:hash)
    end
  end

  describe 'Multi-database configuration' do
    it 'configures secondary database using Rails database.yml references' do
      config_instance = Tasker::Configuration.new
      allow(Tasker::Configuration).to receive(:configuration).and_yield(config_instance).and_return(config_instance)

      Tasker.configuration do |config|
        config.database do |db|
          db.enable_secondary_database = true
          db.name = :tasker # References database.yml configuration
        end

        config.telemetry do |tel|
          tel.service_name = 'tasker-multidb'
        end
      end

      expect(config_instance.database.enable_secondary_database).to be(true)
      expect(config_instance.database.name).to eq(:tasker)
      expect(config_instance.telemetry.service_name).to eq('tasker-multidb')
    end

    it 'supports string database names' do
      config_instance = Tasker::Configuration.new
      allow(Tasker::Configuration).to receive(:configuration).and_yield(config_instance).and_return(config_instance)

      Tasker.configuration do |config|
        config.database do |db|
          db.enable_secondary_database = true
          db.name = 'tasker_production'
        end
      end

      expect(config_instance.database.enable_secondary_database).to be(true)
      expect(config_instance.database.name).to eq('tasker_production')
    end
  end

  describe 'No authentication configuration' do
    it 'maintains backward compatibility with no authentication' do
      config_instance = Tasker::Configuration.new
      allow(Tasker::Configuration).to receive(:configuration).and_yield(config_instance).and_return(config_instance)

      # Don't configure authentication - should default to :none
      Tasker.configuration do |config|
        config.engine do |engine|
          engine.task_handler_directory = 'my_tasks'
        end

        config.telemetry do |tel|
          tel.enabled = false
        end
      end

      expect(config_instance.auth.strategy).to eq(:none)
      expect(config_instance.auth.enabled).to be(false)
      expect(config_instance.database.enable_secondary_database).to be(false)
      expect(config_instance.engine.task_handler_directory).to eq('my_tasks')
      expect(config_instance.telemetry.enabled).to be(false)
    end
  end

  describe 'Full-featured configuration' do
    it 'supports configuring all features together' do
      config_instance = Tasker::Configuration.new
      allow(Tasker::Configuration).to receive(:configuration).and_yield(config_instance).and_return(config_instance)

      Tasker.configuration do |config|
        config.auth do |auth|
          # Authentication
          auth.strategy = :devise
          auth.options = { scope: :admin }

          # Authorization
          auth.enabled = true
          auth.coordinator_class = 'MyApp::TaskerAuthorizationCoordinator'
          auth.user_class = 'AdminUser'
        end

        config.database do |db|
          db.enable_secondary_database = true
          db.name = :tasker_production
        end

        config.telemetry do |tel|
          tel.enabled = true
          tel.service_name = 'enterprise-tasker'
          tel.configure_telemetry(
            batch_events: true,
            buffer_size: 500,
            sampling_rate: 0.8
          )
        end

        config.engine do |engine|
          engine.task_handler_directory = 'workflows'
          engine.identity_strategy = :hash
          engine.default_module_namespace = 'MyApp::Workflows'
        end
      end

      # Verify all settings are preserved
      expect(config_instance.auth.strategy).to eq(:devise)
      expect(config_instance.auth.options[:scope]).to eq(:admin)
      expect(config_instance.auth.enabled).to be(true)
      expect(config_instance.auth.coordinator_class).to eq('MyApp::TaskerAuthorizationCoordinator')
      expect(config_instance.auth.user_class).to eq('AdminUser')

      expect(config_instance.database.enable_secondary_database).to be(true)
      expect(config_instance.database.name).to eq(:tasker_production)

      expect(config_instance.telemetry.enabled).to be(true)
      expect(config_instance.telemetry.service_name).to eq('enterprise-tasker')
      expect(config_instance.telemetry.config[:batch_events]).to be(true)
      expect(config_instance.telemetry.config[:buffer_size]).to eq(500)
      expect(config_instance.telemetry.config[:sampling_rate]).to eq(0.8)

      expect(config_instance.engine.task_handler_directory).to eq('workflows')
      expect(config_instance.engine.identity_strategy).to eq(:hash)
      expect(config_instance.engine.default_module_namespace).to eq('MyApp::Workflows')
    end
  end

  describe 'configuration validation scenarios' do
    it 'allows authorization without authentication' do
      config_instance = Tasker::Configuration.new
      allow(Tasker::Configuration).to receive(:configuration).and_yield(config_instance).and_return(config_instance)

      Tasker.configuration do |config|
        config.auth do |auth|
          auth.strategy = :none
          auth.enabled = true # This should be allowed
          auth.coordinator_class = 'PublicResourceCoordinator'
        end
      end

      expect(config_instance.auth.strategy).to eq(:none)
      expect(config_instance.auth.enabled).to be(true)
      expect(config_instance.auth.coordinator_class).to eq('PublicResourceCoordinator')
    end

    it 'allows database configuration without authentication' do
      config_instance = Tasker::Configuration.new
      allow(Tasker::Configuration).to receive(:configuration).and_yield(config_instance).and_return(config_instance)

      Tasker.configuration do |config|
        config.auth do |auth|
          auth.strategy = :none
        end

        config.database do |db|
          db.enable_secondary_database = true
          db.name = :tasker_analytics
        end
      end

      expect(config_instance.auth.strategy).to eq(:none)
      expect(config_instance.database.enable_secondary_database).to be(true)
      expect(config_instance.database.name).to eq(:tasker_analytics)
    end

    it 'allows telemetry configuration independently' do
      config_instance = Tasker::Configuration.new
      allow(Tasker::Configuration).to receive(:configuration).and_yield(config_instance).and_return(config_instance)

      Tasker.configuration do |config|
        config.telemetry do |tel|
          tel.enabled = false
          tel.service_name = 'minimal-tasker'
        end
      end

      expect(config_instance.telemetry.enabled).to be(false)
      expect(config_instance.telemetry.service_name).to eq('minimal-tasker')
      expect(config_instance.auth.strategy).to eq(:none) # Other configs remain default
      expect(config_instance.database.enable_secondary_database).to be(false)
    end
  end

  describe 'legacy configuration compatibility' do
    it 'supports transitional configuration approaches' do
      config_instance = Tasker::Configuration.new
      allow(Tasker::Configuration).to receive(:configuration).and_yield(config_instance).and_return(config_instance)

      Tasker.configuration do |config|
        # Modern nested configuration
        config.auth do |auth|
          auth.strategy = :devise
          auth.enabled = true
        end

        config.database do |db|
          db.name = :tasker_mixed
        end

        config.telemetry do |tel|
          tel.enabled = false
        end

        config.engine do |engine|
          engine.task_handler_directory = 'mixed_workflows'
        end
      end

      expect(config_instance.auth.strategy).to eq(:devise)
      expect(config_instance.auth.enabled).to be(true)
      expect(config_instance.database.name).to eq(:tasker_mixed)
      expect(config_instance.engine.task_handler_directory).to eq('mixed_workflows')
      expect(config_instance.telemetry.enabled).to be(false)
    end
  end
end
