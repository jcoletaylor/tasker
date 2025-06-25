# typed: false
# frozen_string_literal: true

module Tasker
  module Registry
    # Unified interface validation for all registry systems
    #
    # Provides consistent validation patterns for handlers, subscribers,
    # and plugins including method presence and arity checking.
    class InterfaceValidator
      class << self
        # Validate handler interface compliance
        #
        # @param handler_class [Class] Handler class to validate
        # @raise [ArgumentError] If handler doesn't implement required interface
        def validate_handler!(handler_class)
          # Determine handler type and validate accordingly
          if task_handler?(handler_class)
            validate_task_handler!(handler_class)
          elsif step_handler?(handler_class)
            validate_step_handler!(handler_class)
          else
            # Default to step handler validation for backward compatibility
            validate_step_handler!(handler_class)
          end
        end

        # Validate subscriber interface compliance
        #
        # @param subscriber_class [Class] Subscriber class to validate
        # @raise [ArgumentError] If subscriber doesn't implement required interface
        def validate_subscriber!(subscriber_class)
          validate_instance_methods!(subscriber_class, SUBSCRIBER_INTERFACE)
        end

        # Validate plugin interface compliance
        #
        # @param plugin_instance [Object] Plugin instance to validate
        # @raise [ArgumentError] If plugin doesn't implement required interface
        def validate_plugin!(plugin_instance)
          validate_instance_methods!(plugin_instance.class, PLUGIN_INTERFACE)
          validate_method_arity!(plugin_instance, PLUGIN_ARITY_REQUIREMENTS)
        end

        private

        # Step handler interface definitions (for step handlers with instance method process)
        STEP_HANDLER_INTERFACE = {
          required_class_methods: [],
          optional_class_methods: %i[configure dependencies]
        }.freeze

        STEP_HANDLER_INSTANCE_INTERFACE = {
          required_instance_methods: [:process],
          optional_instance_methods: %i[initialize before_process after_process]
        }.freeze

        # Task handler interface definitions (for task handlers with step_templates)
        TASK_HANDLER_INTERFACE = {
          required_class_methods: [],
          optional_class_methods: [:register_handler]
        }.freeze

        TASK_HANDLER_INSTANCE_INTERFACE = {
          required_instance_methods: [],
          optional_instance_methods: %i[initialize update_annotations step_templates schema]
        }.freeze

        # Subscriber interface definitions
        SUBSCRIBER_INTERFACE = {
          required_instance_methods: [:call],
          optional_instance_methods: %i[initialize filter_events]
        }.freeze

        # Plugin interface definitions
        PLUGIN_INTERFACE = {
          required_instance_methods: %i[export supports_format?],
          optional_instance_methods: %i[supported_formats metadata validate_data]
        }.freeze

        # Plugin method arity requirements
        PLUGIN_ARITY_REQUIREMENTS = {
          export: { min: 1, max: 2 },
          supports_format?: { min: 1, max: 1 }
        }.freeze

        # Validate class methods exist
        #
        # @param klass [Class] Class to validate
        # @param interface [Hash] Interface definition
        # @raise [ArgumentError] If required methods missing
        def validate_class_methods!(klass, interface)
          interface[:required_class_methods]&.each do |method|
            raise ArgumentError, "#{klass} must implement class method #{method}" unless klass.respond_to?(method)
          end
        end

        # Validate instance methods exist
        #
        # @param klass [Class] Class to validate
        # @param interface [Hash] Interface definition
        # @raise [ArgumentError] If required methods missing
        def validate_instance_methods!(klass, interface)
          interface[:required_instance_methods]&.each do |method|
            # Use class-level introspection only - never instantiate classes
            # This covers public, private, and protected methods from the class and its ancestors
            method_exists = klass.instance_methods(true).include?(method) ||
                            klass.private_instance_methods(true).include?(method) ||
                            klass.protected_instance_methods(true).include?(method) ||
                            klass.method_defined?(method) ||
                            klass.private_method_defined?(method) ||
                            klass.protected_method_defined?(method)

            raise ArgumentError, "#{klass} must implement instance method #{method}" unless method_exists
          end
        end

        # Validate method arity for specific methods
        #
        # @param instance [Object] Instance to validate
        # @param arity_requirements [Hash] Arity requirements by method
        # @raise [ArgumentError] If method arity doesn't match requirements
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
                      "#{method} requires too many arguments " \
                      "(min: #{min_required}, max allowed: #{requirements[:max]})"
              end
            else
              unless arity.between?(requirements[:min], requirements[:max])
                raise ArgumentError,
                      "#{method} arity mismatch " \
                      "(expected: #{requirements[:min]}-#{requirements[:max]}, got: #{arity})"
              end
            end
          end
        end

        # Check if class is a task handler
        #
        # @param handler_class [Class] Handler class to check
        # @return [Boolean] True if it's a task handler
        def task_handler?(handler_class)
          # Check if it includes TaskHandler module, has schema method, or has step_templates method
          handler_class.included_modules.any? { |mod| mod.name&.include?('TaskHandler') } ||
            handler_class.instance_methods.include?(:schema) ||
            handler_class.instance_methods.include?(:step_templates)
        end

        # Check if class is a step handler
        #
        # @param handler_class [Class] Handler class to check
        # @return [Boolean] True if it's a step handler
        def step_handler?(handler_class)
          # Check if it includes StepHandler module or has process instance method
          handler_class.included_modules.any? { |mod| mod.name&.include?('StepHandler') } ||
            handler_class.instance_methods.include?(:process)
        end

        # Validate task handler interface
        #
        # @param handler_class [Class] Task handler class to validate
        # @raise [ArgumentError] If validation fails
        def validate_task_handler!(handler_class)
          validate_class_methods!(handler_class, TASK_HANDLER_INTERFACE)
          validate_instance_methods!(handler_class, TASK_HANDLER_INSTANCE_INTERFACE)
        end

        # Validate step handler interface
        #
        # @param handler_class [Class] Step handler class to validate
        # @raise [ArgumentError] If validation fails
        def validate_step_handler!(handler_class)
          validate_class_methods!(handler_class, STEP_HANDLER_INTERFACE)
          validate_instance_methods!(handler_class, STEP_HANDLER_INSTANCE_INTERFACE)
        end
      end
    end
  end
end
