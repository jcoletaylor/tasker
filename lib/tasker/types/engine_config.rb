# frozen_string_literal: true

module Tasker
  module Types
    # Configuration type for core engine settings
    #
    # This configuration handles core Tasker engine settings including task handler
    # directories, identity strategies, and custom event configurations.
    # It provides the same functionality as the original EngineConfiguration but with
    # dry-struct type safety and immutability.
    #
    # @example Basic usage
    #   config = EngineConfig.new(
    #     task_handler_directory: 'app/tasks',
    #     identity_strategy: :hash
    #   )
    #
    # @example Full configuration
    #   config = EngineConfig.new(
    #     task_handler_directory: 'app/tasks',
    #     task_config_directory: 'config/tasks',
    #     default_module_namespace: 'MyApp::Tasks',
    #     identity_strategy: :custom,
    #     identity_strategy_class: 'MyApp::CustomIdentityStrategy',
    #     custom_events_directories: ['config/events', 'lib/events']
    #   )
    class EngineConfig < BaseConfig
      transform_keys(&:to_sym)

      # Directory where task handlers are located
      #
      # @!attribute [r] task_handler_directory
      #   @return [String] Task handler directory path
      attribute :task_handler_directory, Types::String.default('tasks')

      # Directory where task configuration files are located
      #
      # @!attribute [r] task_config_directory
      #   @return [String] Task configuration directory path
      attribute :task_config_directory, Types::String.default('tasker/tasks')

      # Default module namespace for task handlers
      #
      # @!attribute [r] default_module_namespace
      #   @return [String, nil] Default module namespace for generated handlers
      attribute? :default_module_namespace, Types::String.optional.default(nil)

      # The strategy to use for generating task identities
      #
      # @!attribute [r] identity_strategy
      #   @return [Symbol] Identity strategy (:default, :hash, :custom)
      attribute :identity_strategy, Types::Symbol.default(:default)

      # The class name to use for custom identity strategy
      #
      # @!attribute [r] identity_strategy_class
      #   @return [String, nil] Custom identity strategy class name
      attribute? :identity_strategy_class, Types::String.optional.default(nil)

      # Directories to search for custom event YAML files
      #
      # @!attribute [r] custom_events_directories
      #   @return [Array<String>] Custom event directories
      attribute :custom_events_directories, Types::Array.of(Types::String).default(proc {
        default_custom_events_directories
      }.freeze, shared: true)

      # Get default custom events directories
      #
      # @return [Array<String>] Default directories to search for custom events
      def self.default_custom_events_directories
        [
          'config/tasker/events'
        ].freeze
      end

      # Creates and returns an appropriate identity strategy instance
      #
      # @return [Tasker::IdentityStrategy] The identity strategy instance
      # @raise [ArgumentError] If an invalid strategy is specified
      def identity_strategy_instance
        case identity_strategy
        when :default
          Tasker::IdentityStrategy.new
        when :hash
          Tasker::HashIdentityStrategy.new
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
      # Since dry-struct types are immutable, this returns a new instance.
      #
      # @param directories [Array<String>] Additional directories to search for events
      # @return [EngineConfig] New instance with updated directories
      def add_custom_events_directories(*directories)
        new_directories = (custom_events_directories + directories.flatten).uniq
        self.class.new(to_h.merge(custom_events_directories: new_directories))
      end

      # Set custom event directories (replaces the default list)
      #
      # Since dry-struct types are immutable, this returns a new instance.
      #
      # @param directories [Array<String>] Directories to search for events
      # @return [EngineConfig] New instance with updated directories
      def set_custom_events_directories(directories)
        self.class.new(to_h.merge(custom_events_directories: directories.flatten))
      end

      private

      # Use class method for default custom events directories
      def default_custom_events_directories
        self.class.default_custom_events_directories
      end
    end
  end
end
