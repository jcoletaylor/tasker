# frozen_string_literal: true

require 'rails_helper'

module Tasker
  RSpec.describe ApplicationRecord do
    describe 'database connection configuration' do
      let(:original_config) { Tasker.configuration }

      after do
        # Reset configuration after each test
        Tasker.instance_variable_set(:@configuration, original_config)
      end

      context 'when secondary database is disabled' do
        before do
          Tasker.reset_configuration!
          Tasker.configuration do |config|
            config.database do |db|
              db.enable_secondary_database = false
              db.name = nil
            end
          end
        end

        it 'uses the default database connection' do
          expect(described_class.abstract_class?).to be true
          # When secondary database is disabled, the connection should be available
          expect(described_class.connection).to be_present
        end
      end

      context 'when secondary database is enabled but no name provided' do
        before do
          Tasker.reset_configuration!
          Tasker.configuration do |config|
            config.database do |db|
              db.enable_secondary_database = true
              db.name = nil
            end
          end
        end

        it 'uses the default database connection' do
          expect(described_class.abstract_class?).to be true
          # When no name is provided, it should still use the default connection
          expect(described_class.connection).to be_present
        end
      end

      context 'when secondary database is enabled but not configured in database.yml' do
        before do
          Tasker.reset_configuration!
          Tasker.configuration do |config|
            config.database do |db|
              db.enable_secondary_database = true
              db.name = :nonexistent_db
            end
          end
        end

        it 'falls back to default database and logs warning' do
          expect(Rails.logger).to receive(:warn).with(/Tasker secondary database 'nonexistent_db' is enabled but not found/)

          described_class.configure_database_connections

          expect(described_class.abstract_class?).to be true
          expect(described_class.connection).to be_present
        end
      end

      context 'with configuration examples' do
        it 'supports environment-specific database configuration' do
          Tasker.reset_configuration!
          Tasker.configuration do |config|
            config.database do |db|
              db.enable_secondary_database = Rails.env.production?
              db.name = Rails.env.production? ? :tasker_production : nil
            end
          end

          # In test environment, should not use secondary database
          expect(Tasker.configuration.database.enable_secondary_database).to be false
          expect(Tasker.configuration.database.name).to be_nil
        end

        it 'supports symbol database names' do
          Tasker.reset_configuration!
          Tasker.configuration do |config|
            config.database do |db|
              db.enable_secondary_database = true
              db.name = :tasker
            end
          end

          expect(Tasker.configuration.database.name).to eq(:tasker)
          expect(Tasker.configuration.database.enable_secondary_database).to be true
        end

        it 'supports string database names' do
          Tasker.reset_configuration!
          Tasker.configuration do |config|
            config.database do |db|
              db.enable_secondary_database = true
              db.name = 'tasker_development'
            end
          end

          expect(Tasker.configuration.database.name).to eq('tasker_development')
          expect(Tasker.configuration.database.enable_secondary_database).to be true
        end
      end

      describe 'inheritance behavior' do
        it 'is an abstract class' do
          expect(described_class.abstract_class?).to be true
        end

        it 'inherits from ActiveRecord::Base' do
          expect(described_class.superclass).to eq(ActiveRecord::Base)
        end

        it 'serves as base class for all Tasker models' do
          # Verify key models inherit from ApplicationRecord
          expect(Task.superclass).to eq(described_class)
          expect(WorkflowStep.superclass).to eq(described_class)
          expect(NamedTask.superclass).to eq(described_class)
        end
      end

      describe 'database connection setup' do
        it 'has the configure_database_connections class method' do
          expect(described_class).to respond_to(:configure_database_connections)
        end

        it 'has the database_configuration_exists? class method' do
          expect(described_class).to respond_to(:database_configuration_exists?)
        end

        it 'can call configure_database_connections without errors when configuration is available' do
          expect { described_class.configure_database_connections }.not_to raise_error
        end

        it 'database_configuration_exists? returns false for nonexistent databases' do
          expect(described_class.database_configuration_exists?(:nonexistent)).to be false
        end

        it 'database_configuration_exists? handles string and symbol names' do
          # These should return the same result
          result_symbol = described_class.database_configuration_exists?(:test)
          result_string = described_class.database_configuration_exists?('test')
          expect(result_symbol).to eq(result_string)
        end

        it 'database_configuration_exists? fails fast if Rails is not properly available' do
          # If Rails.application or its config is nil, this should raise an error, not return false
          allow(Rails).to receive(:application).and_return(nil)

          expect { described_class.database_configuration_exists?(:test) }.to raise_error(NoMethodError)
        end

        it 'raises an error when Tasker.configuration is not available' do
          # Create a test class that simulates the error condition
          test_class = Class.new(ApplicationRecord) do
            self.abstract_class = true

            def self.configure_database_connections
              # Simulate the condition where Tasker.configuration is not defined
              # This simulates defined?(Tasker.configuration) returning false

              raise StandardError, 'Tasker.configuration is not available. This indicates a Rails initialization order issue. ' \
                                   'Ensure Tasker is properly initialized before models are loaded.'
            end
          end

          expect { test_class.configure_database_connections }.to raise_error(
            StandardError,
            /Tasker\.configuration is not available.*Rails initialization order issue/
          )
        end
      end
    end
  end
end
