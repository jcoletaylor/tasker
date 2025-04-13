# frozen_string_literal: true

module Tasker
  class Configuration
    attr_accessor :task_handler_directory, :task_config_directory, :default_module_namespace,
                  :identity_strategy, :identity_strategy_class, :filter_parameters, :telemetry_filter_mask,
                  :service_name

    def initialize
      @task_handler_directory = 'tasks'
      @task_config_directory = 'tasks'
      @default_module_namespace = nil
      @identity_strategy = :default
      @identity_strategy_class = nil
      @filter_parameters = default_filter_parameters
      @telemetry_filter_mask = '[FILTERED]'
      @service_name = 'tasker'
    end

    def default_filter_parameters
      if Rails.application.config.filter_parameters.any?
        Rails.application.config.filter_parameters
      else
        %i[passw email secret token _key crypt salt certificate otp ssn]
      end
    end

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

    def parameter_filter
      @parameter_filter ||= if filter_parameters.any?
                              ActiveSupport::ParameterFilter.new(filter_parameters, mask: telemetry_filter_mask)
                            end
    end

    # Global configuration
    def self.configuration
      @configuration ||= Configuration.new

      # Yield if a block is given for backwards compatibility
      yield(@configuration) if block_given?

      @configuration
    end

    def self.reset_configuration!
      @configuration = Configuration.new
    end
  end
end
