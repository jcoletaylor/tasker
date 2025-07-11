# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Configuration, 'Database Configuration' do
  let(:config) { described_class.new }

  # Store original configuration before tests
  around do |example|
    original_config = described_class.instance_variable_get(:@configuration)
    example.run
  ensure
    # Restore original configuration after each test
    described_class.instance_variable_set(:@configuration, original_config)
  end

  describe 'nested database configuration' do
    it 'provides access to database configuration block' do
      expect(config.database).to be_a(Tasker::Types::DatabaseConfig)
    end

    it 'yields configuration proxy in block' do
      expect { |b| config.database(&b) }.to yield_with_args(Tasker::Configuration::ConfigurationProxy)
    end

    it 'supports method chaining' do
      result = config.database do |db|
        db.name = :tasker_db
      end

      expect(result).to be_a(Tasker::Types::DatabaseConfig)
      expect(result.name).to eq(:tasker_db)
    end
  end

  describe 'database configuration defaults' do
    it 'has correct default values' do
      db = config.database
      expect(db.name).to be_nil
      expect(db.enable_secondary_database).to be(false)
    end
  end

  describe 'database configuration setters' do
    it 'allows setting database name using block configuration' do
      config.database do |db|
        db.name = :tasker_test
      end
      expect(config.database.name).to eq(:tasker_test)
    end

    it 'allows setting enable_secondary_database using block configuration' do
      config.database do |db|
        db.enable_secondary_database = true
      end
      expect(config.database.enable_secondary_database).to be(true)
    end

    it 'supports block configuration' do
      config.database do |db|
        db.name = :test_database
        db.enable_secondary_database = true
      end

      expect(config.database.name).to eq(:test_database)
      expect(config.database.enable_secondary_database).to be(true)
    end
  end

  describe 'integration scenarios' do
    context 'with production multi-database setup' do
      it 'configures for secondary database' do
        config.database do |db|
          db.name = :global_tasker_db
          db.enable_secondary_database = true
        end

        expect(config.database.name).to eq(:global_tasker_db)
        expect(config.database.enable_secondary_database).to be(true)
      end
    end

    context 'with single database setup' do
      it 'uses default application database' do
        config.database do |db|
          db.enable_secondary_database = false
        end

        expect(config.database.name).to be_nil
        expect(config.database.enable_secondary_database).to be(false)
      end
    end

    context 'with test database setup' do
      it 'configures for test environment' do
        config.database do |db|
          db.name = :test
          db.enable_secondary_database = false
        end

        expect(config.database.name).to eq(:test)
        expect(config.database.enable_secondary_database).to be(false)
      end
    end
  end

  describe 'global configuration integration' do
    it 'works with Tasker::Configuration.configuration' do
      described_class.configuration do |config|
        config.database do |db|
          db.name = :global_db
          db.enable_secondary_database = true
        end
      end

      expect(described_class.configuration.database.name).to eq(:global_db)
      expect(described_class.configuration.database.enable_secondary_database).to be(true)
    end
  end
end
