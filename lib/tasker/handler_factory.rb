# typed: false
# frozen_string_literal: true

require_relative 'events/custom_registry'

module Tasker
  # Factory for creating task handler instances
  #
  # This class maintains a registry of task handlers by name and dependent system,
  # providing namespaced handler organization while maintaining backward compatibility.
  # It follows the Singleton pattern to ensure a single registry.
  class HandlerFactory
    include Singleton

    # @return [Hash] Registered handler classes by dependent system and handler name
    attr_accessor :handler_classes

    # @return [Set] Set of registered namespaces for efficient enumeration
    attr_accessor :namespaces

    # Initialize a new handler factory
    #
    # @return [HandlerFactory] A new handler factory instance
    def initialize
      self.handler_classes ||= ActiveSupport::HashWithIndifferentAccess.new
      self.namespaces ||= Set.new([:default])
    end

    # Get a task handler instance by name and optional dependent system
    #
    # @param name [String, Symbol] The name of the handler to retrieve
    # @param dependent_system [String, Symbol] The dependent system namespace (defaults to 'default')
    # @return [Object] An instance of the requested task handler
    # @raise [Tasker::ProceduralError] If no handler is registered with the given name in the specified system
    def get(name, namespace_name: :default, version: '0.1.0')
      namespace_name = namespace_name.to_sym
      name_sym = name.to_sym

      # Direct namespace lookup - allows same name in different systems
      handler_class = handler_classes.dig(namespace_name, name_sym, version)
      raise_handler_not_found(name, namespace_name, version) unless handler_class

      instantiate_handler(handler_class)
    end

    # Register a task handler class with a name and optional dependent system
    #
    # @param name [String, Symbol] The name to register the handler under
    # @param class_name [Class, String] The handler class to register
    # @param dependent_system [String, Symbol] The dependent system namespace (defaults to 'default')
    # @return [void]
    # @raise [StandardError] If custom event configuration fails (fail fast)
    def register(name, class_or_class_name, namespace_name: :default, version: '0.1.0')
      name_sym = name.to_sym
      namespace_name = namespace_name.to_sym

      # Validate custom event configuration BEFORE modifying registry state
      # This ensures atomic registration - either fully succeeds or fully fails
      normalized_class = normalize_class_name(class_or_class_name)
      discover_and_register_custom_events(class_or_class_name)

      # Only modify registry state after successful configuration validation
      handler_classes[namespace_name] ||= ActiveSupport::HashWithIndifferentAccess.new
      handler_classes[namespace_name][name_sym] ||= ActiveSupport::HashWithIndifferentAccess.new
      handler_classes[namespace_name][name_sym][version] = normalized_class
      namespaces.add(namespace_name)
    end

    # List handlers, optionally filtered by namespace
    #
    # @param namespace [String, Symbol, nil] Optional namespace filter
    # @return [Hash] Handlers hash, either for specific namespace or all namespaces
    def list_handlers(namespace: nil)
      if namespace
        handler_classes[namespace.to_s] || ActiveSupport::HashWithIndifferentAccess.new
      else
        handler_classes
      end
    end

    # Get list of all registered namespaces
    #
    # @return [Array<String>] Array of namespace strings
    def registered_namespaces
      namespaces.to_a
    end

    private

    # Normalize class name for consistent storage
    #
    # @param class_or_class_name [Class, String] The handler class to normalize
    # @return [Class, String] Normalized class representation
    def normalize_class_name(class_or_class_name)
      if class_or_class_name.is_a?(Class)
        # Store the class directly for anonymous classes
        class_or_class_name
      else
        # Store as string for named classes (original behavior)
        class_or_class_name.to_s
      end
    end

    # Instantiate a handler from class or string
    #
    # @param handler_class [Class, String] The handler class to instantiate
    # @return [Object] New handler instance
    # @raise [Tasker::ProceduralError] If handler class cannot be instantiated
    def instantiate_handler(handler_class)
      if handler_class.is_a?(Class)
        # Direct class instantiation (used in tests with anonymous classes)
        handler_class.new
      else
        # String class name instantiation (used in production)
        handler_class.to_s.camelize.constantize.new
      end
    rescue NameError => e
      raise(Tasker::ProceduralError, "Failed to instantiate handler: #{e.message}")
    end

    # Raise appropriate error for handler not found
    #
    # @param name [String, Symbol] Handler name that was not found
    # @param namespace_name [String] The namespace that was searched
    # @param version [String] The version that was searched
    # @raise [Tasker::ProceduralError] Handler not found error
    def raise_handler_not_found(name, namespace_name, version)
      raise(Tasker::ProceduralError, "No task handler for #{name}") if namespace_name == :default

      raise(Tasker::ProceduralError,
            "No task handler for #{name} in namespace #{namespace_name} and version #{version}")
    end

    # Automatically discover and register custom events from step handlers
    #
    # @param handler_class [Class, String] The handler class to scan for custom events
    # @return [void]
    # @raise [Tasker::ConfigurationError] If custom event configuration fails
    def discover_and_register_custom_events(handler_class)
      # Get the actual class object
      klass = if handler_class.is_a?(Class)
                handler_class
              else
                handler_class.to_s.camelize.constantize
              end

      # Check if this is a step handler class (has custom_event_configuration method)
      if klass.respond_to?(:custom_event_configuration)
        # This is a step handler class - register its custom events directly
        # Configuration failures should be visible errors, not silent warnings
        class_events = klass.custom_event_configuration
        register_custom_events_from_config(class_events, klass)
        return
      end

      # Check if this is a task handler class (has step_templates instance method)
      # We need to avoid instantiating task handler classes as it causes recursion
      nil unless klass.instance_methods(false).include?(:step_templates)

      # For task handler classes, we'll register custom events from step template definitions
      # but we can't safely instantiate the class here due to recursion
      # Instead, we'll let the step handlers register their own events when they're loaded
      # This is a limitation we accept to avoid the recursive instantiation issue

      # NOTE: YAML-based custom events in step templates will be handled during
      # the task building process, not here
    end

    # Register custom events from configuration (either class-based or YAML-based)
    #
    # @param events_config [Array<Hash>] Array of event configurations
    # @param handler_class [Class] The handler class that can fire these events
    # @return [void]
    def register_custom_events_from_config(events_config, handler_class)
      events_config.each do |event_config|
        # Support both symbol and string keys
        event_name = event_config[:name] || event_config['name']
        description = event_config[:description] || event_config['description'] ||
                      "Custom event from #{handler_class.name}"

        next unless event_name

        # Add the handler class to fired_by array automatically
        fired_by = [handler_class.name]

        Tasker::Events::CustomRegistry.instance.register_event(
          event_name,
          description: description,
          fired_by: fired_by
        )
      end
    end
  end
end
