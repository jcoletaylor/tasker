# frozen_string_literal: true

module Tasker
  # Configuration class for the Tasker gem
  #
  # Handles global configuration options including directory paths,
  # identity strategies, and telemetry settings.
  class Configuration
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
    # @!attribute [rw] filter_parameters
    #   @return [Array<Symbol>] Parameters to filter from logs and telemetry
    # @!attribute [rw] telemetry_filter_mask
    #   @return [String] The mask to use when filtering sensitive parameters
    # @!attribute [rw] otel_telemetry_service_name
    #   @return [String] Service name for OpenTelemetry
    # @!attribute [rw] otel_telemetry_service_version
    #   @return [String] Service version for OpenTelemetry
    attr_accessor :task_handler_directory, :task_config_directory, :default_module_namespace,
                  :identity_strategy, :identity_strategy_class, :filter_parameters, :telemetry_filter_mask,
                  :otel_telemetry_service_name, :otel_telemetry_service_version

    # Initialize a new configuration with default values
    #
    # @return [Configuration] A new configuration instance
    def initialize
      @task_handler_directory = 'tasks'
      @task_config_directory = 'tasks'
      @default_module_namespace = nil
      @identity_strategy = :default
      @identity_strategy_class = nil
      @filter_parameters = default_filter_parameters
      @telemetry_filter_mask = '[FILTERED]'
      @otel_telemetry_service_name = 'tasker'
      @otel_telemetry_service_version = Tasker::VERSION
    end

    # Get the default filter parameters from Rails or use a default set
    #
    # @return [Array<Symbol>] Default parameters to filter
    def default_filter_parameters
      if Rails.application.config.filter_parameters.any?
        Rails.application.config.filter_parameters
      else
        %i[passw email secret token _key crypt salt certificate otp ssn]
      end
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

    # Get or create a parameter filter for sensitive data
    #
    # @return [ActiveSupport::ParameterFilter, nil] The parameter filter
    def parameter_filter
      @parameter_filter ||= if filter_parameters.any?
                              ActiveSupport::ParameterFilter.new(filter_parameters, mask: telemetry_filter_mask)
                            end
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
