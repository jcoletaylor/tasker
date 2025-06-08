# frozen_string_literal: true

# typed: false

module Tasker
  # Abstract base class for all Tasker models that provides optional secondary database support.
  #
  # This class follows Rails multi-database conventions using the `connects_to` API.
  # When secondary database is enabled, it connects to a database named 'tasker' in database.yml.
  #
  # @example Basic usage with shared database (default)
  #   Tasker.configuration do |config|
  #     config.database.enable_secondary_database = false
  #   end
  #
  # @example Using a dedicated Tasker database
  #   Tasker.configuration do |config|
  #     config.database.enable_secondary_database = true
  #     config.database.name = :tasker
  #   end
  #
  #   # In database.yml:
  #   production:
  #     primary:
  #       database: my_primary_database
  #       adapter: postgresql
  #     tasker:
  #       database: my_tasker_database
  #       adapter: postgresql
  #
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true

    # Configure database connections based on Tasker configuration
    # This follows Rails multi-database conventions but only when database is actually available
    def self.configure_database_connections
      # Ensure Tasker configuration is available - fail fast if not
      unless defined?(Tasker.configuration)
        raise StandardError, "Tasker.configuration is not available. This indicates a Rails initialization order issue. " \
                           "Ensure Tasker is properly initialized before models are loaded."
      end

      config = Tasker.configuration.database
      if config.enable_secondary_database && config.name.present?
        # Check if the database configuration actually exists before calling connects_to
        if database_configuration_exists?(config.name)
          # Use connects_to for proper Rails multi-database support
          connects_to database: { writing: config.name.to_sym, reading: config.name.to_sym }
        else
          Rails.logger.warn "Tasker secondary database '#{config.name}' is enabled but not found in database.yml. Using default database."
        end
      end
    rescue ActiveRecord::DatabaseConfigurationError => e
      # Log database configuration errors but don't fail startup - this allows for
      # environments where the secondary database might not be available
      Rails.logger.warn "Tasker database configuration error: #{e.message}"
    end

    # Check if a database configuration exists in the current environment
    def self.database_configuration_exists?(db_name)
      Rails.application.config.database_configuration.key?(db_name.to_s)
    end

    # Call the connection configuration method
    configure_database_connections
  end
end
