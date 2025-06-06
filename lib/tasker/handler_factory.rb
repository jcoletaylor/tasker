# typed: false
# frozen_string_literal: true

require_relative 'events/custom_registry'

module Tasker
  # Factory for creating task handler instances
  #
  # This class maintains a registry of task handlers by name and
  # provides methods to retrieve handler instances when needed.
  # It follows the Singleton pattern to ensure a single registry.
  class HandlerFactory
    include Singleton

    # @return [Hash] Registered handler classes by handler name
    attr_accessor :handler_classes

    # Initialize a new handler factory
    #
    # @return [HandlerFactory] A new handler factory instance
    def initialize
      self.handler_classes ||= {}
    end

    # Get a task handler instance by name
    #
    # @param name [String, Symbol] The name of the handler to retrieve
    # @return [Object] An instance of the requested task handler
    # @raise [Tasker::ProceduralError] If no handler is registered with the given name
    def get(name)
      handler_class = handler_classes[name.to_sym]
      raise(Tasker::ProceduralError, "No task handler for #{name}") unless handler_class

      # Handle both direct class objects and string class names
      if handler_class.is_a?(Class)
        # Direct class registration (used in tests with anonymous classes)
        handler_class.new
      else
        # String class name registration (used in production)
        handler_class.to_s.camelize.constantize.new
      end
    rescue NameError => e
      raise(Tasker::ProceduralError, "No task handler for #{name}: #{e.message}")
    end

    # Register a task handler class with a name
    #
    # @param name [String, Symbol] The name to register the handler under
    # @param class_name [Class, String] The handler class to register
    # @return [void]
    def register(name, class_name)
      self.handler_classes[name.to_sym] = if class_name.is_a?(Class)
                                            # Store the class directly for anonymous classes
                                            class_name
                                          else
                                            # Store as string for named classes (original behavior)
                                            class_name.to_s
                                          end

      # Automatically discover and register custom events from step handlers
      discover_and_register_custom_events(class_name)
    end

    private

    # Automatically discover and register custom events from step handlers
    #
    # @param handler_class [Class, String] The handler class to scan for custom events
    # @return [void]
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
        begin
          class_events = klass.custom_event_configuration
          register_custom_events_from_config(class_events, klass)
        rescue StandardError => e
          # Don't let custom event registration failures break handler registration
          Rails.logger.warn "Failed to register custom events for #{klass}: #{e.message}" if defined?(Rails)
        end
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
        description = event_config[:description] || event_config['description'] || "Custom event from #{handler_class.name}"

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
