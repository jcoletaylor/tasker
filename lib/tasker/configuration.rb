# frozen_string_literal: true

module Tasker
  class Configuration
    attr_accessor :task_handler_directory, :task_config_directory, :default_module_namespace,
                  :identity_strategy, :identity_strategy_class,
                  :enable_telemetry, :telemetry_adapters, :telemetry_adapter_classes

    def initialize
      @task_handler_directory = 'tasks'
      @task_config_directory = 'tasks'
      @default_module_namespace = nil
      @identity_strategy = :default
      @identity_strategy_class = nil
      @enable_telemetry = false
      @telemetry_adapters = [:default]
      @telemetry_adapter_classes = []
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

    def telemetry_adapter_instances
      return [] unless enable_telemetry

      # Ensure adapters are always in an array
      adapters = Array(@telemetry_adapters)
      adapter_classes = Array(@telemetry_adapter_classes)

      # Build all adapter instances
      instances = []

      adapters.each_with_index do |adapter_type, index|
        instance = case adapter_type
                   when :default
                     require 'tasker/telemetry/logger_adapter'
                     Telemetry::LoggerAdapter.new
                   when :opentelemetry
                     begin
                       require 'tasker/telemetry/opentelemetry_adapter'
                       Telemetry::OpenTelemetryAdapter.new
                     rescue LoadError => e
                       Rails.logger.error "OpenTelemetry gems not found: #{e.message}" if defined?(Rails)
                       nil
                     end
                   when :custom
                     class_name = adapter_classes[index]
                     if class_name.nil?
                       raise ArgumentError,
                             "Custom telemetry adapter at index #{index} selected but no corresponding class provided"
                     end

                     begin
                       class_name.to_s.constantize.new
                     rescue NameError => e
                       raise ArgumentError, "Invalid telemetry adapter class: #{e.message}"
                     end
                   else
                     raise ArgumentError, "Unknown telemetry adapter: #{adapter_type}"
                   end

        instances << instance if instance
      end

      instances
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
