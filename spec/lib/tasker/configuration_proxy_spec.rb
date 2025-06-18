# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Configuration::ConfigurationProxy, 'Configuration Proxy Implementation' do
  let(:config) { Tasker::Configuration.new }

  # Store original configuration before tests
  around do |example|
    original_config = Tasker::Configuration.instance_variable_get(:@configuration)
    example.run
  ensure
    # Restore original configuration after each test
    Tasker::Configuration.instance_variable_set(:@configuration, original_config)
  end

  describe 'ConfigurationProxy behavior' do
    it 'supports property assignment and reading' do
      proxy = described_class.new(test_value: 'initial')

      # Test initial value reading
      expect(proxy.test_value).to eq('initial')

      # Test property assignment
      proxy.test_value = 'updated'
      expect(proxy.test_value).to eq('updated')

      # Test new property assignment
      proxy.new_property = 'new_value'
      expect(proxy.new_property).to eq('new_value')
    end

    it 'converts to hash correctly' do
      proxy = described_class.new(key1: 'value1', key2: 'value2')
      proxy.key3 = 'value3'

      hash = proxy.to_h
      expect(hash).to be_a(Hash)
      expect(hash).to eq({ key1: 'value1', key2: 'value2', key3: 'value3' })
    end

    it 'transforms string keys to symbols' do
      proxy = described_class.new('string_key' => 'value')
      expect(proxy.string_key).to eq('value')
      expect(proxy.to_h).to eq({ string_key: 'value' })
    end

    it 'raises NoMethodError for non-existent properties without assignment' do
      proxy = described_class.new
      expect { proxy.non_existent_property }.to raise_error(NoMethodError)
    end

    it 'responds to assignment methods correctly' do
      proxy = described_class.new
      expect(proxy.respond_to?(:any_property=)).to be(true)
      expect(proxy.respond_to?(:existing_key)).to be(false)

      proxy.existing_key = 'value'
      expect(proxy.respond_to?(:existing_key)).to be(true)
    end
  end

  describe 'integration with all configuration types' do
    describe 'auth configuration' do
      it 'works with ConfigurationProxy for block-based configuration' do
        config.auth do |auth|
          expect(auth).to be_a(described_class)
          auth.authentication_enabled = true
          auth.authenticator_class = 'TestAuthenticator'
          auth.authorization_enabled = true
        end

        auth_config = config.auth
        expect(auth_config).to be_a(Tasker::Types::AuthConfig)
        expect(auth_config.authentication_enabled).to be(true)
        expect(auth_config.authenticator_class).to eq('TestAuthenticator')
        expect(auth_config.authorization_enabled).to be(true)
      end
    end

    describe 'database configuration' do
      it 'works with ConfigurationProxy for block-based configuration' do
        config.database do |db|
          expect(db).to be_a(described_class)
          db.name = :test_database
          db.enable_secondary_database = true
        end

        db_config = config.database
        expect(db_config).to be_a(Tasker::Types::DatabaseConfig)
        expect(db_config.name).to eq(:test_database)
        expect(db_config.enable_secondary_database).to be(true)
      end
    end

    describe 'telemetry configuration' do
      it 'works with ConfigurationProxy for block-based configuration' do
        config.telemetry do |telemetry|
          expect(telemetry).to be_a(described_class)
          telemetry.enabled = false
          telemetry.service_name = 'test_service'
        end

        telemetry_config = config.telemetry
        expect(telemetry_config).to be_a(Tasker::Types::TelemetryConfig)
        expect(telemetry_config.enabled).to be(false)
        expect(telemetry_config.service_name).to eq('test_service')
      end
    end

    describe 'engine configuration' do
      it 'works with ConfigurationProxy for block-based configuration' do
        config.engine do |engine|
          expect(engine).to be_a(described_class)
          engine.task_handler_directory = 'custom_tasks'
          engine.identity_strategy = :hash
        end

        engine_config = config.engine
        expect(engine_config).to be_a(Tasker::Types::EngineConfig)
        expect(engine_config.task_handler_directory).to eq('custom_tasks')
        expect(engine_config.identity_strategy).to eq(:hash)
      end
    end

    describe 'health configuration' do
      it 'works with ConfigurationProxy for block-based configuration' do
        config.health do |health|
          expect(health).to be_a(described_class)
          health.status_requires_authentication = false
          health.readiness_timeout_seconds = 15.0
        end

        health_config = config.health
        expect(health_config).to be_a(Tasker::Types::HealthConfig)
        expect(health_config.status_requires_authentication).to be(false)
        expect(health_config.readiness_timeout_seconds).to eq(15.0)
      end
    end

    describe 'dependency_graph configuration' do
      it 'works with ConfigurationProxy for block-based configuration' do
        config.dependency_graph do |graph|
          expect(graph).to be_a(described_class)
          graph.weight_multipliers = { complexity: 2.0, priority: 3.0 }
          graph.threshold_constants = { bottleneck_threshold: 0.9 }
        end

        graph_config = config.dependency_graph
        expect(graph_config).to be_a(Tasker::Types::DependencyGraphConfig)
        expect(graph_config.weight_multipliers[:complexity]).to eq(2.0)
        expect(graph_config.weight_multipliers[:priority]).to eq(3.0)
        expect(graph_config.threshold_constants[:bottleneck_threshold]).to eq(0.9)
      end
    end

    describe 'backoff configuration' do
      it 'works with ConfigurationProxy for block-based configuration' do
        config.backoff do |backoff|
          expect(backoff).to be_a(described_class)
          backoff.default_backoff_seconds = [2, 4, 8, 16]
          backoff.max_backoff_seconds = 600
          backoff.jitter_enabled = false
        end

        backoff_config = config.backoff
        expect(backoff_config).to be_a(Tasker::Types::BackoffConfig)
        expect(backoff_config.default_backoff_seconds).to eq([2, 4, 8, 16])
        expect(backoff_config.max_backoff_seconds).to eq(600)
        expect(backoff_config.jitter_enabled).to be(false)
      end
    end
  end

  describe 'global configuration integration' do
    it 'works with Tasker.configuration and ConfigurationProxy' do
      Tasker.configuration do |global_config|
        # Test multiple configuration types in one block
        global_config.auth do |auth|
          auth.authentication_enabled = true
          auth.authenticator_class = 'GlobalAuthenticator'
        end

        global_config.database do |db|
          db.name = :global_db
          db.enable_secondary_database = true
        end

        global_config.dependency_graph do |graph|
          graph.weight_multipliers = { complexity: 1.8, priority: 2.5 }
        end

        global_config.backoff do |backoff|
          backoff.max_backoff_seconds = 900
          backoff.jitter_enabled = true
        end
      end

      # Verify all configurations were set correctly
      global_config = Tasker.configuration

      expect(global_config.auth.authentication_enabled).to be(true)
      expect(global_config.auth.authenticator_class).to eq('GlobalAuthenticator')

      expect(global_config.database.name).to eq(:global_db)
      expect(global_config.database.enable_secondary_database).to be(true)

      expect(global_config.dependency_graph.weight_multipliers[:complexity]).to eq(1.8)
      expect(global_config.dependency_graph.weight_multipliers[:priority]).to eq(2.5)

      expect(global_config.backoff.max_backoff_seconds).to eq(900)
      expect(global_config.backoff.jitter_enabled).to be(true)
    end
  end

  describe 'dry-struct validation integration' do
    it 'validates configuration through dry-struct when proxy values are converted' do
      # This should work - valid configuration
      expect do
        config.auth do |auth|
          auth.authentication_enabled = true
          auth.authenticator_class = 'ValidAuthenticator'
        end
      end.not_to raise_error

      # This should raise a validation error from dry-struct
      expect do
        config.backoff do |backoff|
          backoff.max_backoff_seconds = 'invalid_string' # Should be integer
        end
      end.to raise_error(Dry::Struct::Error)
    end
  end

  describe 'backward compatibility' do
    it 'maintains the same API as the original configuration system' do
      # Test that existing configuration patterns still work exactly the same
      config.auth do |auth|
        auth.authentication_enabled = true
        auth.authenticator_class = 'DeviseAuthenticator'
        auth.current_user_method = :current_user
        auth.authenticate_user_method = :authenticate_user!
        auth.authorization_enabled = true
        auth.authorization_coordinator_class = 'MyApp::AuthorizationCoordinator'
        auth.user_class = 'User'
      end

      auth_config = config.auth
      expect(auth_config.authentication_enabled).to be(true)
      expect(auth_config.authenticator_class).to eq('DeviseAuthenticator')
      expect(auth_config.current_user_method).to eq(:current_user)
      expect(auth_config.authenticate_user_method).to eq(:authenticate_user!)
      expect(auth_config.authorization_enabled).to be(true)
      expect(auth_config.authorization_coordinator_class).to eq('MyApp::AuthorizationCoordinator')
      expect(auth_config.user_class).to eq('User')
    end
  end

  describe 'immutability preservation' do
    it 'creates new dry-struct instances instead of mutating existing ones' do
      # Set initial configuration
      config.auth do |auth|
        auth.authentication_enabled = false
        auth.authenticator_class = nil
      end

      original_auth_config = config.auth
      original_object_id = original_auth_config.object_id

      # Update configuration
      config.auth do |auth|
        auth.authentication_enabled = true
        auth.authenticator_class = 'NewAuthenticator'
      end

      new_auth_config = config.auth

      # Should be a different object (immutable dry-struct behavior)
      expect(new_auth_config.object_id).not_to eq(original_object_id)
      expect(new_auth_config.authentication_enabled).to be(true)
      expect(new_auth_config.authenticator_class).to eq('NewAuthenticator')
    end
  end
end
