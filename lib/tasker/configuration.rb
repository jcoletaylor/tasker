# frozen_string_literal: true

module Tasker
  class Configuration
    attr_accessor :task_handler_directory, :task_config_directory, :default_module_namespace,
                  :identity_strategy, :identity_strategy_class,
                  :observability

    class ObservabilityConfiguration
      attr_accessor :telemetry_adapters, :observer, :enable_telemetry

      def initialize
        @enable_telemetry = false
        @telemetry_adapters = ['Tasker::Observability::LoggerAdapter']
        @observer = 'Tasker::Observability::LifecycleObserver'
      end

      def telemetry_adapter_instances
        return [] unless enable_telemetry

        # Ensure adapters are always in an array
        adapters = Array(@telemetry_adapters)

        # Build all adapter instances
        adapters.map do |adapter|
          adapter.to_s.classify.constantize.new
        end
      end

      def observer_instance
        return nil unless enable_telemetry

        @observer_instance ||= @observer.to_s.classify.constantize.new(telemetry_adapter_instances)
      rescue NameError => e
        raise ArgumentError, "Invalid lifecycle observer class #{@observer}: #{e.message}"
      end

      def register_observer!
        observer_instance&.register!
      end
    end

    def initialize
      @task_handler_directory = 'tasks'
      @task_config_directory = 'tasks'
      @default_module_namespace = nil
      @identity_strategy = :default
      @identity_strategy_class = nil
      @observability = ObservabilityConfiguration.new
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

    # Global configuration
    def self.configuration
      @configuration ||= Configuration.new
      @configuration.observability ||= ObservabilityConfiguration.new

      # Yield if a block is given for backwards compatibility
      yield(@configuration) if block_given?

      @configuration
    end

    def self.reset_configuration!
      @configuration = Configuration.new
      @configuration.observability = ObservabilityConfiguration.new
    end
  end
end
