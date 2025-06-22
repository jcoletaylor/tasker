# frozen_string_literal: true

module Tasker
  module Types
    # Configuration type for database settings
    #
    # This configuration handles database connection settings for Tasker.
    # It provides the same functionality as the original DatabaseConfiguration but with
    # dry-struct type safety and immutability.
    #
    # @example Basic usage
    #   config = DatabaseConfig.new(
    #     name: :secondary,
    #     enable_secondary_database: true
    #   )
    #
    # @example Default configuration
    #   config = DatabaseConfig.new
    #   # Uses default database, no secondary database
    class DatabaseConfig < BaseConfig
      transform_keys(&:to_sym)

      # Database name or configuration key type that accepts strings or symbols
      NameType = Types::String | Types::Symbol

      # Named database configuration from database.yml
      #
      # @!attribute [r] name
      #   @return [String, Symbol, nil] Named database configuration key
      attribute? :name, NameType.optional.default(nil)

      # Whether to use a secondary database for Tasker models
      #
      # @!attribute [r] enable_secondary_database
      #   @return [Boolean] Whether to use secondary database
      attribute :enable_secondary_database, Types::Bool.default(false)
    end
  end
end
