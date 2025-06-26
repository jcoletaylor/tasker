# typed: false
# frozen_string_literal: true

require 'json-schema'
require 'concurrent'
require_relative '../events/custom_registry'

module Tasker
  module TaskHandler
    # Class methods for task handlers
    #
    # This module provides class-level functionality for task handlers,
    # including step template definition and handler registration.
    module ClassMethods
      # Helper class for defining step templates in task handlers
      class StepTemplateDefiner
        # @return [Array<Tasker::Types::StepTemplate>] The defined step templates
        attr_reader :step_templates

        # @return [Class] The class where templates are being defined
        attr_reader :klass

        # @return [Hash<String, String>] Mapping of step names to handler class names
        attr_reader :step_handler_class_map

        # @return [Hash<String, Object>] Mapping of step names to handler configs
        attr_reader :step_handler_config_map

        # Create a new step template definer
        #
        # @param klass [Class] The class where templates are being defined
        # @return [StepTemplateDefiner] A new step template definer
        def initialize(klass)
          @klass = klass
          @step_templates = []
          @step_handler_class_map = {}
          @step_handler_config_map = {}
        end

        # Define a new step template
        #
        # @param kwargs [Hash] The step template attributes
        # @option kwargs [String] :dependent_system The system that this step depends on
        # @option kwargs [String] :name The name identifier for this step
        # @option kwargs [String] :description A description of what this step does
        # @option kwargs [Boolean] :default_retryable Whether this step can be retried
        # @option kwargs [Integer] :default_retry_limit The maximum number of retry attempts
        # @option kwargs [Boolean] :skippable Whether this step can be skipped
        # @option kwargs [Class] :handler_class The class that implements the step's logic
        # @option kwargs [String, nil] :depends_on_step Name of a step this depends on
        # @option kwargs [Array<String>] :depends_on_steps Names of steps this depends on
        # @option kwargs [Object, nil] :handler_config Configuration for the step handler
        # @option kwargs [Array<Hash>] :custom_events Custom events this step can publish
        # @return [void]
        def define(**kwargs)
          dependent_system = kwargs.fetch(:dependent_system, Tasker::Constants::UNKNOWN)
          name = kwargs.fetch(:name)
          handler_class = kwargs.fetch(:handler_class)
          description = kwargs.fetch(:description, name)
          default_retryable = kwargs.fetch(:default_retryable, true)
          default_retry_limit = kwargs.fetch(:default_retry_limit, 3)
          skippable = kwargs.fetch(:skippable, false)
          depends_on_step = kwargs.fetch(:depends_on_step, nil)
          depends_on_steps = kwargs.fetch(:depends_on_steps, [])
          handler_config = kwargs.fetch(:handler_config, nil)
          custom_events = kwargs.fetch(:custom_events, [])

          # Register custom events (both YAML-based and class-based) when step template is defined
          register_custom_events_for_handler(custom_events, handler_class)

          @step_templates << Tasker::Types::StepTemplate.new(
            dependent_system: dependent_system,
            name: name,
            description: description,
            default_retryable: default_retryable,
            default_retry_limit: default_retry_limit,
            skippable: skippable,
            handler_class: handler_class,
            depends_on_step: depends_on_step,
            depends_on_steps: depends_on_steps,
            handler_config: handler_config,
            custom_events: custom_events
          )
        end

        # Register the mapping of step names to handler classes and configs
        #
        # @return [void]
        def register_class_map
          @step_templates.each do |template|
            @step_handler_class_map[template.name] = template.handler_class.to_s
            @step_handler_config_map[template.name] = template.handler_config
          end
        end

        private

        # Register both YAML-based and class-based custom events from the step handler
        #
        # @param custom_events [Array<Hash>] Array of custom event configurations from YAML
        # @param handler_class [Class] The handler class that can fire these events
        # @return [void]
        def register_custom_events_for_handler(custom_events, handler_class)
          YamlEventRegistrar.register(custom_events, handler_class)
          register_class_based_custom_events(handler_class)
        end

        # Register class-based custom events from a step handler class
        #
        # @param handler_class [Class] The step handler class to scan for custom events
        # @return [void]
        def register_class_based_custom_events(handler_class)
          ClassBasedEventRegistrar.register(handler_class)
        end

        # Service class to register YAML-based custom events
        # Reduces complexity by organizing YAML event registration logic
        class YamlEventRegistrar
          class << self
            # Register YAML-based custom events
            #
            # @param custom_events [Array<Hash>] Array of custom event configurations from YAML
            # @param handler_class [Class] The handler class that can fire these events
            # @return [void]
            def register(custom_events, handler_class)
              custom_events.each do |event_config|
                register_single_yaml_event(event_config, handler_class)
              end
            end

            private

            # Register a single YAML-based custom event
            #
            # @param event_config [Hash] Event configuration
            # @param handler_class [Class] Handler class
            # @return [void]
            def register_single_yaml_event(event_config, handler_class)
              event_name = extract_event_name(event_config)
              return unless event_name

              description = extract_event_description(event_config, handler_class)
              fired_by = [handler_class.name]

              safely_register_event(event_name, description, fired_by, handler_class)
            end

            # Extract event name from configuration
            #
            # @param event_config [Hash] Event configuration
            # @return [String, nil] Event name
            def extract_event_name(event_config)
              event_config[:name] || event_config['name']
            end

            # Extract event description from configuration
            #
            # @param event_config [Hash] Event configuration
            # @param handler_class [Class] Handler class
            # @return [String] Event description
            def extract_event_description(event_config, handler_class)
              event_config[:description] ||
                event_config['description'] ||
                "Custom event from #{handler_class.name}"
            end

            # Register event - fail fast on configuration errors
            #
            # @param event_name [String] Event name
            # @param description [String] Event description
            # @param fired_by [Array] Array of handler class names
            # @param handler_class [Class] Handler class for error context
            # @return [void]
            # @raise [StandardError] If event registration fails (fail fast)
            def safely_register_event(event_name, description, fired_by, _handler_class)
              Tasker::Events::CustomRegistry.instance.register_event(
                event_name,
                description: description,
                fired_by: fired_by
              )
              # Configuration errors should be visible, not silently logged
            end

            # Log registration failure
            #
            # @param event_name [String] Event name that failed
            # @param handler_class [Class] Handler class
            # @param error [StandardError] Error that occurred
            # @return [void]
            def log_registration_failure(event_name, handler_class, error)
              return unless defined?(Rails)

              Rails.logger.warn "Failed to register custom event #{event_name} from #{handler_class}: #{error.message}"
            end
          end
        end

        # Service class to register class-based custom events
        # Reduces complexity by organizing event registration logic
        class ClassBasedEventRegistrar
          class << self
            # Register class-based custom events from a step handler class
            #
            # @param handler_class [Class] The step handler class to scan for custom events
            # @return [void]
            def register(handler_class)
              return unless has_custom_event_configuration?(handler_class)

              safely_register_events(handler_class)
            end

            private

            # Check if handler class has custom event configuration
            #
            # @param handler_class [Class] The step handler class
            # @return [Boolean] True if class has custom event configuration
            def has_custom_event_configuration?(handler_class)
              handler_class.respond_to?(:custom_event_configuration)
            end

            # Register all custom events from handler class - fail fast on configuration errors
            #
            # @param handler_class [Class] The step handler class
            # @return [void]
            # @raise [StandardError] If custom event configuration fails (fail fast)
            def safely_register_events(handler_class)
              class_events = get_class_events(handler_class)
              class_events.each { |event_config| register_single_event(event_config, handler_class) }
              # Configuration errors should be visible, not silently logged
            end

            # Get custom events from handler class configuration
            #
            # @param handler_class [Class] The step handler class
            # @return [Array] Array of event configurations
            def get_class_events(handler_class)
              handler_class.custom_event_configuration
            end

            # Register a single custom event
            #
            # @param event_config [Hash] The event configuration
            # @param handler_class [Class] The step handler class
            # @return [void]
            def register_single_event(event_config, handler_class)
              event_name = extract_event_name(event_config)
              return unless event_name

              description = extract_event_description(event_config, handler_class)
              fired_by = [handler_class.name]

              Tasker::Events::CustomRegistry.instance.register_event(
                event_name,
                description: description,
                fired_by: fired_by
              )
            end

            # Extract event name from configuration
            #
            # @param event_config [Hash] The event configuration
            # @return [String, nil] The event name
            def extract_event_name(event_config)
              event_config[:name] || event_config['name']
            end

            # Extract event description from configuration
            #
            # @param event_config [Hash] The event configuration
            # @param handler_class [Class] The step handler class
            # @return [String] The event description
            def extract_event_description(event_config, handler_class)
              event_config[:description] ||
                event_config['description'] ||
                "Custom event from #{handler_class.name}"
            end

            # Log registration failure
            #
            # @param handler_class [Class] The step handler class
            # @param error [StandardError] The error that occurred
            # @return [void]
            def log_registration_failure(handler_class, error)
              return unless defined?(Rails)

              Rails.logger.warn "Failed to register class-based custom events from #{handler_class}: #{error.message}"
            end
          end
        end
      end

      # Define step templates for a task handler
      #
      # @yield [StepTemplateDefiner] A block to define step templates
      # @return [void]
      def define_step_templates
        definer = StepTemplateDefiner.new(self)
        yield(definer)
        definer.klass.define_method(:step_templates) do
          definer.step_templates
        end
        definer.register_class_map
        definer.klass.define_method(:step_handler_class_map) do
          definer.step_handler_class_map
        end
        definer.klass.define_method(:step_handler_config_map) do
          definer.step_handler_config_map
        end
      end

      # Register a task handler with the handler factory
      #
      # @param name [String, Symbol] The name to register the handler under
      # @param concurrent [Boolean] Whether to use concurrent processing
      # @return [void]
      def register_handler(name, namespace_name: 'default', version: '0.1.0', concurrent: true)
        # Register the handler with the factory
        Tasker::HandlerFactory.instance.register(name, self, namespace_name: namespace_name, version: version,
                                                             replace: true)
      end
    end
  end
end
