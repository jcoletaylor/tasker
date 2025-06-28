# frozen_string_literal: true

module Tasker
  # Configuration class for the Tasker gem
  #
  # Handles global configuration options with nested configuration blocks
  # for better organization and discoverability.
  #
  # All configuration types are now implemented using dry-struct for type safety,
  # immutability, and consistent validation patterns.
  class Configuration
    # Simple proxy object for configuration blocks that provides dot-notation access
    # to hash values without the overhead of OpenStruct.
    #
    # This enables clean configuration syntax like:
    #   config.auth do |auth|
    #     auth.authentication_enabled = true
    #     auth.authenticator_class = 'MyAuth'
    #   end
    #
    # While maintaining the benefits of dry-struct validation and immutability.
    class ConfigurationProxy
      # Initialize a new configuration proxy with hash data
      #
      # @param hash [Hash] The hash data to wrap
      def initialize(hash = {})
        @hash = hash.transform_keys(&:to_sym)
      end

      # Handle dynamic method calls for configuration access
      #
      # @param method_name [Symbol] The method being called
      # @param args [Array] Arguments passed to the method
      def method_missing(method_name, *args)
        if method_name.to_s.end_with?('=')
          # Setter: config.authentication_enabled = true
          key = method_name.to_s.chomp('=').to_sym
          @hash[key] = args.first
        elsif @hash.key?(method_name.to_sym)
          # Getter: config.authentication_enabled
          @hash[method_name.to_sym]
        else
          super
        end
      end

      # Check if the proxy responds to a given method
      #
      # @param method_name [Symbol] The method name to check
      # @param include_private [Boolean] Whether to include private methods
      # @return [Boolean] True if the method is supported
      def respond_to_missing?(method_name, include_private = false)
        method_name.to_s.end_with?('=') || @hash.key?(method_name.to_sym) || super
      end

      # Convert the proxy back to a hash for dry-struct creation
      #
      # @return [Hash] The underlying hash data
      def to_h
        @hash
      end
    end

    # Specialized configuration proxy for telemetry settings
    # Handles special methods specific to TelemetryConfig
    class TelemetryConfigurationProxy < ConfigurationProxy
      # Handle telemetry-specific configuration method
      #
      # @param options [Hash] Telemetry configuration options
      def configure_telemetry(options = {})
        current_config = @hash[:config] || {}
        @hash[:config] = current_config.merge(options)
      end

      # Check if the proxy responds to telemetry-specific methods
      #
      # @param method_name [Symbol] The method name to check
      # @param include_private [Boolean] Whether to include private methods
      # @return [Boolean] True if the method is supported
      def respond_to_missing?(method_name, include_private = false)
        method_name.to_s == 'configure_telemetry' || super
      end
    end

    # Initialize a new configuration with default values
    #
    # @return [Configuration] A new configuration instance
    def initialize
      # Initialize nested configurations using dry-struct types
      @auth_config = Tasker::Types::AuthConfig.new
      @database_config = Tasker::Types::DatabaseConfig.new
      @telemetry_config = Tasker::Types::TelemetryConfig.new
      @engine_config = Tasker::Types::EngineConfig.new
      @health_config = Tasker::Types::HealthConfig.new
      @dependency_graph_config = Tasker::Types::DependencyGraphConfig.new
      @backoff_config = Tasker::Types::BackoffConfig.new
      @execution_config = Tasker::Types::ExecutionConfig.new
    end

    # Reset configuration to defaults (useful for testing)
    def reset!
      @auth_config = Tasker::Types::AuthConfig.new
      @database_config = Tasker::Types::DatabaseConfig.new
      @telemetry_config = Tasker::Types::TelemetryConfig.new
      @engine_config = Tasker::Types::EngineConfig.new
      @health_config = Tasker::Types::HealthConfig.new
      @dependency_graph_config = Tasker::Types::DependencyGraphConfig.new
      @backoff_config = Tasker::Types::BackoffConfig.new
      @execution_config = Tasker::Types::ExecutionConfig.new
    end

    # Create a deep copy of the configuration
    #
    # Since dry-struct types are immutable, we don't need to duplicate them
    def dup
      new_config = super
      new_config.instance_variable_set(:@auth_config, @auth_config)
      new_config.instance_variable_set(:@database_config, @database_config)
      new_config.instance_variable_set(:@telemetry_config, @telemetry_config)
      new_config.instance_variable_set(:@engine_config, @engine_config)
      new_config.instance_variable_set(:@health_config, @health_config)
      new_config.instance_variable_set(:@dependency_graph_config, @dependency_graph_config)
      new_config.instance_variable_set(:@backoff_config, @backoff_config)
      new_config.instance_variable_set(:@execution_config, @execution_config)
      new_config
    end

    # Configure authentication and authorization settings
    #
    # @yield [ConfigurationProxy] A configuration object for setting auth options
    # @return [Tasker::Types::AuthConfig] The auth configuration instance
    def auth
      if block_given?
        # For block configuration, we need to create a new instance with the block's values
        current_values = @auth_config.to_h
        yield_config = ConfigurationProxy.new(current_values)
        yield(yield_config)
        @auth_config = Tasker::Types::AuthConfig.new(yield_config.to_h)
      end
      @auth_config
    end

    # Alias for auth configuration for backward compatibility
    # @return [Tasker::Types::AuthConfig] The authentication configuration instance
    def authentication
      @auth_config
    end

    # Configure database settings
    #
    # @yield [ConfigurationProxy] A configuration object for setting database options
    # @return [Tasker::Types::DatabaseConfig] The database configuration instance
    def database
      if block_given?
        # For block configuration, we need to create a new instance with the block's values
        current_values = @database_config.to_h
        yield_config = ConfigurationProxy.new(current_values)
        yield(yield_config)
        @database_config = Tasker::Types::DatabaseConfig.new(yield_config.to_h)
      end
      @database_config
    end

    # Configure telemetry and observability settings
    #
    # @yield [TelemetryConfigurationProxy] A configuration object for setting telemetry options
    # @return [Tasker::Types::TelemetryConfig] The telemetry configuration instance
    def telemetry
      if block_given?
        # For block configuration, we need to create a new instance with the block's values
        current_values = @telemetry_config.to_h
        yield_config = TelemetryConfigurationProxy.new(current_values)
        yield(yield_config)
        @telemetry_config = Tasker::Types::TelemetryConfig.new(yield_config.to_h)
      end
      @telemetry_config
    end

    # Configure core engine settings
    #
    # @yield [ConfigurationProxy] A configuration object for setting engine options
    # @return [Tasker::Types::EngineConfig] The engine configuration instance
    def engine
      if block_given?
        # For block configuration, we need to create a new instance with the block's values
        current_values = @engine_config.to_h
        yield_config = ConfigurationProxy.new(current_values)
        yield(yield_config)
        @engine_config = Tasker::Types::EngineConfig.new(yield_config.to_h)
      end
      @engine_config
    end

    # Configure health check settings
    #
    # @yield [ConfigurationProxy] A configuration object for setting health options
    # @return [Tasker::Types::HealthConfig] The health configuration instance
    def health
      if block_given?
        # For block configuration, we need to create a new instance with the block's values
        current_values = @health_config.to_h
        yield_config = ConfigurationProxy.new(current_values)
        yield(yield_config)
        @health_config = Tasker::Types::HealthConfig.new(yield_config.to_h)
      end
      @health_config
    end

    # Configure dependency graph calculation settings
    #
    # @yield [ConfigurationProxy] A configuration object for setting dependency graph options
    # @return [Tasker::Types::DependencyGraphConfig] The dependency graph configuration instance
    def dependency_graph
      if block_given?
        # For block configuration, we need to create a new instance with the block's values
        current_values = @dependency_graph_config.to_h
        yield_config = ConfigurationProxy.new(current_values)
        yield(yield_config)
        @dependency_graph_config = Tasker::Types::DependencyGraphConfig.new(yield_config.to_h)
      end
      @dependency_graph_config
    end

    # Configure backoff calculation settings
    #
    # @yield [ConfigurationProxy] A configuration object for setting backoff options
    # @return [Tasker::Types::BackoffConfig] The backoff configuration instance
    def backoff
      if block_given?
        # For block configuration, we need to create a new instance with the block's values
        current_values = @backoff_config.to_h
        yield_config = ConfigurationProxy.new(current_values)
        yield(yield_config)
        @backoff_config = Tasker::Types::BackoffConfig.new(yield_config.to_h)
      end
      @backoff_config
    end

    # Configure step execution and concurrency settings
    #
    # @yield [ConfigurationProxy] A configuration object for setting execution options
    # @return [Tasker::Types::ExecutionConfig] The execution configuration instance
    def execution
      if block_given?
        # For block configuration, we need to create a new instance with the block's values
        current_values = @execution_config.to_h
        yield_config = ConfigurationProxy.new(current_values)
        yield(yield_config)
        @execution_config = Tasker::Types::ExecutionConfig.new(yield_config.to_h)
      end
      @execution_config
    end

    # Validate required configuration settings for system health
    # Used by health check endpoints to ensure system is properly configured
    # @return [true] if valid
    # @raise [StandardError] if invalid configuration found
    def validate_required_settings
      errors = []

      # Database connectivity check
      errors << 'Database connection required' unless database_connected?

      # Authentication configuration validation (if enabled)
      if auth.authentication_enabled && auth.authenticator_class.blank?
        errors << 'Authentication enabled but no authenticator_class configured'
      end

      # Health configuration validation (dry-struct handles validation automatically)
      @health_config&.validate!

      raise StandardError, errors.join(', ') if errors.any?

      true
    end

    private

    # Check if database is connected and available
    # @return [Boolean] true if database is connected
    def database_connected?
      ActiveRecord::Base.connection.active?
    rescue StandardError
      false
    end

    # Get or create the global configuration
    #
    # @yield [Configuration] The configuration instance if a block is given
    # @return [Configuration] The configuration instance
    def self.configuration
      @configuration ||= Configuration.new

      # Yield if a block is given for backwards compatibility
      yield(@configuration) if block_given?

      @configuration
    end

    # Reset the configuration to default values
    #
    # @return [Configuration] A new configuration instance
    def self.reset_configuration!
      @configuration = Configuration.new
    end
  end
end
