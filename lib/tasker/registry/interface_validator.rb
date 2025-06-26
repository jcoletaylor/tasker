# typed: false
# frozen_string_literal: true

module Tasker
  module Registry
    # Unified interface validation for all registry systems
    #
    # Provides consistent validation patterns for handlers, subscribers, plugins,
    # and other registry items to ensure they implement required interfaces.
    class InterfaceValidator
      class << self
        # Validate a task handler class
        #
        # @param handler_class [Class] The handler class to validate
        # @raise [ArgumentError] If validation fails
        def validate_handler!(handler_class)
          validate_class_methods!(handler_class, HANDLER_INTERFACE)
          validate_instance_methods!(handler_class, HANDLER_INSTANCE_INTERFACE)
        end

        # Validate an event subscriber class
        #
        # @param subscriber_class [Class] The subscriber class to validate
        # @raise [ArgumentError] If validation fails
        def validate_subscriber!(subscriber_class)
          validate_instance_methods!(subscriber_class, SUBSCRIBER_INTERFACE)
        end

        # Validate a telemetry plugin instance
        #
        # @param plugin_instance [Object] The plugin instance to validate
        # @raise [ArgumentError] If validation fails
        def validate_plugin!(plugin_instance)
          validate_instance_methods!(plugin_instance.class, PLUGIN_INTERFACE)
          validate_method_arity!(plugin_instance, PLUGIN_ARITY_REQUIREMENTS)
        end

        # Validate an export coordinator plugin
        #
        # @param plugin_instance [Object] The export plugin instance to validate
        # @raise [ArgumentError] If validation fails
        def validate_export_plugin!(plugin_instance)
          validate_instance_methods!(plugin_instance.class, EXPORT_PLUGIN_INTERFACE)
          validate_method_arity!(plugin_instance, EXPORT_PLUGIN_ARITY_REQUIREMENTS)
        end

        private

        # Interface definitions for different types of registry items
        HANDLER_INTERFACE = {
          required_class_methods: [],
          optional_class_methods: %i[process configure dependencies]
        }.freeze

        HANDLER_INSTANCE_INTERFACE = {
          required_instance_methods: [],
          optional_instance_methods: %i[initialize before_process after_process step_templates]
        }.freeze

        SUBSCRIBER_INTERFACE = {
          required_instance_methods: [:call],
          optional_instance_methods: %i[initialize filter_events]
        }.freeze

        PLUGIN_INTERFACE = {
          required_instance_methods: %i[export supports_format?],
          optional_instance_methods: %i[supported_formats metadata validate_data]
        }.freeze

        EXPORT_PLUGIN_INTERFACE = {
          required_instance_methods: %i[export supports_format?],
          optional_instance_methods: %i[supported_formats on_cache_sync on_export_request on_export_complete]
        }.freeze

        # Method arity requirements for validation
        PLUGIN_ARITY_REQUIREMENTS = {
          export: { min: 1, max: 2 },
          supports_format?: { min: 1, max: 1 }
        }.freeze

        EXPORT_PLUGIN_ARITY_REQUIREMENTS = {
          export: { min: 1, max: 2 },
          supports_format?: { min: 1, max: 1 },
          on_cache_sync: { min: 0, max: 1 },
          on_export_request: { min: 0, max: 1 },
          on_export_complete: { min: 0, max: 1 }
        }.freeze

        # Validate that a class implements required class methods
        #
        # @param klass [Class] The class to validate
        # @param interface [Hash] Interface definition with required/optional methods
        def validate_class_methods!(klass, interface)
          interface[:required_class_methods]&.each do |method|
            raise ArgumentError, "#{klass} must implement class method #{method}" unless klass.respond_to?(method)
          end
        end

        # Validate that a class implements required instance methods
        #
        # @param klass [Class] The class to validate
        # @param interface [Hash] Interface definition with required/optional methods
        def validate_instance_methods!(klass, interface)
          interface[:required_instance_methods]&.each do |method|
            unless klass.instance_methods.include?(method)
              raise ArgumentError, "#{klass} must implement instance method #{method}"
            end
          end
        end

        # Validate method arity for specific methods
        #
        # @param instance [Object] The instance to validate
        # @param arity_requirements [Hash] Method name => arity requirements mapping
        def validate_method_arity!(instance, arity_requirements)
          arity_requirements.each do |method, requirements|
            next unless instance.respond_to?(method)

            method_obj = instance.method(method)
            arity = method_obj.arity

            # Handle negative arity (variable arguments)
            if arity.negative?
              min_required = arity.abs - 1
              if min_required > requirements[:max]
                raise ArgumentError,
                      "#{method} requires too many arguments (min: #{min_required}, max allowed: #{requirements[:max]})"
              end
            else
              unless arity.between?(requirements[:min], requirements[:max])
                raise ArgumentError,
                      "#{method} arity mismatch (expected: #{requirements[:min]}-#{requirements[:max]}, got: #{arity})"
              end
            end
          end
        end
      end
    end
  end
end
