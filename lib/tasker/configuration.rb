# frozen_string_literal: true

module Tasker
  # Configuration class for the Tasker gem
  #
  # Handles global configuration options with nested configuration blocks
  # for better organization and discoverability.
  class Configuration
    # Nested configuration class for authentication and authorization settings
    class AuthConfiguration
      # @!attribute [rw] authentication_enabled
      #   @return [Boolean] Whether authentication is enabled
      # @!attribute [rw] authenticator_class
      #   @return [String, nil] Class name for the authenticator (nil means no authentication)
      # @!attribute [rw] current_user_method
      #   @return [Symbol] Method name to get the current user
      # @!attribute [rw] authenticate_user_method
      #   @return [Symbol] Method name to authenticate the user
      # @!attribute [rw] authorization_enabled
      #   @return [Boolean] Whether authorization is enabled
      # @!attribute [rw] authorization_coordinator_class
      #   @return [String] Class name for the authorization coordinator
      # @!attribute [rw] user_class
      #   @return [String, nil] Class name for the authorizable user class
      attr_accessor :authentication_enabled, :authenticator_class, :current_user_method, :authenticate_user_method,
                    :authorization_enabled, :authorization_coordinator_class, :user_class

      def initialize
        # Authentication defaults (disabled by default)
        @authentication_enabled = false
        @authenticator_class = nil
        @current_user_method = :current_user
        @authenticate_user_method = :authenticate_user!

        # Authorization defaults (disabled by default)
        @authorization_enabled = false
        @authorization_coordinator_class = 'Tasker::Authorization::BaseCoordinator'
        @user_class = nil
      end
    end

    # Nested configuration class for database settings
    class DatabaseConfiguration
      # @!attribute [rw] name
      #   @return [String, Symbol, nil] Named database configuration from database.yml
      # @!attribute [rw] enable_secondary_database
      #   @return [Boolean] Whether to use a secondary database for Tasker models
      attr_accessor :name, :enable_secondary_database

      def initialize
        @name = nil
        @enable_secondary_database = false
      end
    end

    # Nested configuration class for telemetry and observability settings
    class TelemetryConfiguration
      # @!attribute [rw] enabled
      #   @return [Boolean] Whether telemetry is enabled
      # @!attribute [rw] service_name
      #   @return [String] Service name for OpenTelemetry
      # @!attribute [rw] service_version
      #   @return [String] Service version for OpenTelemetry
      # @!attribute [rw] filter_parameters
      #   @return [Array<Symbol>] Parameters to filter from logs and telemetry
      # @!attribute [rw] filter_mask
      #   @return [String] The mask to use when filtering sensitive parameters
      # @!attribute [rw] config
      #   @return [Hash] Advanced telemetry configuration options
      attr_accessor :enabled, :service_name, :service_version, :filter_parameters, :filter_mask, :config

      def initialize
        @enabled = true
        @service_name = 'tasker'
        @service_version = Tasker::VERSION
        @filter_parameters = default_filter_parameters
        @filter_mask = '[FILTERED]'
        @config = default_telemetry_config
      end

      # Get the default filter parameters from Rails or use a default set
      #
      # @return [Array<Symbol>] Default parameters to filter
      def default_filter_parameters
        if Rails.application.config.filter_parameters.any?
          Rails.application.config.filter_parameters.dup
        else
          %i[passw email secret token _key crypt salt certificate otp ssn]
        end
      end

      # Get default telemetry configuration
      #
      # @return [Hash] Default telemetry configuration options
      def default_telemetry_config
        {
          # Batch processing options
          batch_events: false, # Set to true to enable event batching
          buffer_size: 100,           # Maximum events to buffer before flushing
          flush_interval: 5.seconds,  # Maximum time between flushes

          # Event filtering options
          filtered_events: [], # List of event names to skip recording

          # Performance options
          enable_memoization: true, # Cache frequently accessed attributes

          # Production optimizations
          async_processing: false, # Process events asynchronously (future enhancement)
          sampling_rate: 1.0 # Sample rate for events (1.0 = 100%, 0.1 = 10%)
        }
      end

      # Update telemetry configuration with custom options
      #
      # @param options [Hash] Custom telemetry configuration options
      # @return [Hash] The updated telemetry configuration
      def configure_telemetry(options = {})
        @config = default_telemetry_config.merge(options)
      end

      # Check if telemetry batching is enabled
      #
      # @return [Boolean] True if batching is enabled
      def batching_enabled?
        config[:batch_events] || false
      end

      # Get or create a parameter filter for sensitive data
      #
      # @return [ActiveSupport::ParameterFilter, nil] The parameter filter
      def parameter_filter
        @parameter_filter ||= if filter_parameters.any?
                                ActiveSupport::ParameterFilter.new(filter_parameters, mask: filter_mask)
                              end
      end
    end

    # Nested configuration class for core engine settings
    class EngineConfiguration
      # @!attribute [rw] task_handler_directory
      #   @return [String] Directory where task handlers are located
      # @!attribute [rw] task_config_directory
      #   @return [String] Directory where task configuration files are located
      # @!attribute [rw] default_module_namespace
      #   @return [String, nil] Default module namespace for task handlers
      # @!attribute [rw] identity_strategy
      #   @return [Symbol] The strategy to use for generating task identities (:default, :hash, :custom)
      # @!attribute [rw] identity_strategy_class
      #   @return [String, nil] The class name to use for custom identity strategy
      # @!attribute [rw] custom_events_directories
      #   @return [Array<String>] Directories to search for custom event YAML files
      attr_accessor :task_handler_directory, :task_config_directory, :default_module_namespace,
                    :identity_strategy, :identity_strategy_class, :custom_events_directories

      def initialize
        @task_handler_directory = 'tasks'
        @task_config_directory = 'tasker/tasks'
        @default_module_namespace = nil
        @identity_strategy = :default
        @identity_strategy_class = nil
        @custom_events_directories = default_custom_events_directories
      end

      # Get default custom events directories
      #
      # @return [Array<String>] Default directories to search for custom events
      def default_custom_events_directories
        [
          'config/tasker/events'
        ]
      end

      # Creates and returns an appropriate identity strategy instance
      #
      # @return [Tasker::IdentityStrategy] The identity strategy instance
      # @raise [ArgumentError] If an invalid strategy is specified
      def identity_strategy_instance
        case identity_strategy
        when :default
          IdentityStrategy.new
        when :hash
          HashIdentityStrategy.new
        when :custom
          if identity_strategy_class.nil?
            raise ArgumentError, 'Custom identity strategy selected but no identity_strategy_class provided'
          end

          begin
            identity_strategy_class.constantize.new
          rescue NameError => e
            raise ArgumentError, "Invalid identity_strategy_class: #{e.message}"
          end
        else
          raise ArgumentError, "Unknown identity_strategy: #{identity_strategy}"
        end
      end

      # Add custom event directories to the existing configuration
      #
      # @param directories [Array<String>] Additional directories to search for events
      # @return [Array<String>] The updated directories list
      def add_custom_events_directories(*directories)
        @custom_events_directories = (custom_events_directories + directories.flatten).uniq
      end

      # Set custom event directories (replaces the default list)
      #
      # @param directories [Array<String>] Directories to search for events
      # @return [Array<String>] The new directories list
      def set_custom_events_directories(directories)
        @custom_events_directories = directories.flatten
      end
    end

    # Initialize a new configuration with default values
    #
    # @return [Configuration] A new configuration instance
    def initialize
      # Initialize nested configurations
      @auth_config = AuthConfiguration.new
      @database_config = DatabaseConfiguration.new
      @telemetry_config = TelemetryConfiguration.new
      @engine_config = EngineConfiguration.new
    end

    # Reset configuration to defaults (useful for testing)
    def reset!
      @auth_config = AuthConfiguration.new
      @database_config = DatabaseConfiguration.new
      @telemetry_config = TelemetryConfiguration.new
      @engine_config = EngineConfiguration.new
    end

    # Configure authentication and authorization settings
    #
    # @yield [AuthConfiguration] The auth configuration instance if a block is given
    # @return [AuthConfiguration] The auth configuration instance
    def auth
      yield(@auth_config) if block_given?
      @auth_config
    end

    # Configure database settings
    #
    # @yield [DatabaseConfiguration] The database configuration instance if a block is given
    # @return [DatabaseConfiguration] The database configuration instance
    def database
      yield(@database_config) if block_given?
      @database_config
    end

    # Configure telemetry and observability settings
    #
    # @yield [TelemetryConfiguration] The telemetry configuration instance if a block is given
    # @return [TelemetryConfiguration] The telemetry configuration instance
    def telemetry
      yield(@telemetry_config) if block_given?
      @telemetry_config
    end

    # Configure core engine settings
    #
    # @yield [EngineConfiguration] The engine configuration instance if a block is given
    # @return [EngineConfiguration] The engine configuration instance
    def engine
      yield(@engine_config) if block_given?
      @engine_config
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
