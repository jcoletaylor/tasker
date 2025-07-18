# typed: false
# frozen_string_literal: true

require_relative 'events/custom_registry'
require_relative 'registry/base_registry'
require_relative 'registry/interface_validator'
require 'concurrent-ruby'

module Tasker
  # Factory for creating task handler instances
  #
  # This class maintains a registry of task handlers by name and dependent system,
  # providing namespaced handler organization while maintaining backward compatibility.
  # It follows the Singleton pattern to ensure a single registry and uses thread-safe
  # storage with modern registry patterns.
  class HandlerFactory < Registry::BaseRegistry
    include Singleton

    # @return [Concurrent::Hash] Thread-safe registered handler classes by dependent system and handler name
    attr_reader :handler_classes

    # @return [Set] Set of registered namespaces for efficient enumeration
    attr_reader :namespaces

    # Initialize a new handler factory
    #
    # @return [HandlerFactory] A new handler factory instance
    def initialize
      super
      @handler_classes = Concurrent::Hash.new
      @namespaces = Set.new([:default])
      log_registry_operation('initialized', namespaces: @namespaces.to_a)
    end

    # Get a task handler instance by name and optional dependent system
    #
    # @param name [String, Symbol] The name of the handler to retrieve
    # @param namespace_name [String, Symbol] The dependent system namespace (defaults to 'default')
    # @param version [String] The version of the handler (defaults to '0.1.0')
    # @return [Object] An instance of the requested task handler
    # @raise [Tasker::ProceduralError] If no handler is registered with the given name in the specified system
    def get(name, namespace_name: :default, version: '0.1.0')
      namespace_name = namespace_name.to_sym
      name_sym = name.to_sym

      # Find the handler class within the mutex lock
      handler_class = thread_safe_operation do
        # Direct namespace lookup - allows same name in different systems
        handler_class = @handler_classes.dig(namespace_name, name_sym, version)
        raise_handler_not_found(name, namespace_name, version) unless handler_class

        log_registry_operation('handler_retrieved',
                               entity_type: 'task_handler',
                               entity_id: "#{namespace_name}/#{name_sym}/#{version}",
                               handler_class: handler_class.is_a?(Class) ? handler_class.name : handler_class)

        handler_class
      end

      # Instantiate the handler OUTSIDE the mutex lock to avoid recursive locking
      # when ConfiguredTask handlers try to register themselves during instantiation
      instantiate_handler(handler_class)
    end

    # Register a task handler class with a name and optional dependent system
    #
    # @param name [String, Symbol] The name to register the handler under
    # @param class_or_class_name [Class, String] The handler class to register
    # @param namespace_name [String, Symbol] The dependent system namespace (defaults to 'default')
    # @param version [String] The version of the handler (defaults to '0.1.0')
    # @param options [Hash] Additional registration options
    # @option options [Boolean] :replace (false) Whether to replace existing handler
    # @return [Boolean] True if registration successful
    # @raise [StandardError] If custom event configuration fails (fail fast)
    # @raise [ArgumentError] If handler already exists and replace is false
    def register(name, class_or_class_name, namespace_name: :default, version: '0.1.0', **options)
      name_sym = name.to_sym
      namespace_name = namespace_name.to_sym
      replace = options.fetch(:replace, false)

      thread_safe_operation do
        # Validate custom event configuration BEFORE modifying registry state
        # This ensures atomic registration - either fully succeeds or fully fails
        normalized_class = normalize_class_name(class_or_class_name)

        # Validate handler interface using unified validator
        begin
          Registry::InterfaceValidator.validate_handler!(normalized_class.is_a?(Class) ? normalized_class : normalized_class.constantize)
        rescue ArgumentError => e
          log_validation_failure('task_handler', "#{namespace_name}/#{name_sym}/#{version}", e.message)
          raise
        end

        discover_and_register_custom_events(class_or_class_name)

        # Initialize nested hash structure
        @handler_classes[namespace_name] ||= Concurrent::Hash.new
        @handler_classes[namespace_name][name_sym] ||= Concurrent::Hash.new

        # Check for existing handler
        entity_id = "#{namespace_name}/#{name_sym}/#{version}"
        if @handler_classes[namespace_name][name_sym].key?(version) && !replace
          raise ArgumentError,
                "Handler '#{name_sym}' already registered in namespace '#{namespace_name}' version '#{version}'. Use replace: true to override."
        end

        # Log replacement if needed
        if @handler_classes[namespace_name][name_sym].key?(version)
          existing_class = @handler_classes[namespace_name][name_sym][version]
          log_unregistration('task_handler', entity_id,
                             existing_class.is_a?(Class) ? existing_class : existing_class.constantize)
        end

        # Register handler
        @handler_classes[namespace_name][name_sym][version] = normalized_class
        @namespaces.add(namespace_name)

        # Log successful registration
        log_registration('task_handler', entity_id,
                         normalized_class.is_a?(Class) ? normalized_class : normalized_class.constantize,
                         { namespace_name: namespace_name, version: version, **options })

        true
      end
    end

    # List handlers, optionally filtered by namespace
    #
    # @param namespace [String, Symbol, nil] Optional namespace filter
    # @return [Hash] Handlers hash, either for specific namespace or all namespaces
    def list_handlers(namespace: nil)
      if namespace
        @handler_classes[namespace.to_sym] || Concurrent::Hash.new
      else
        @handler_classes.dup
      end
    end

    # Get list of all registered namespaces
    #
    # @return [Array<Symbol>] Array of namespace symbols
    def registered_namespaces
      @namespaces.to_a
    end

    # Get comprehensive registry statistics
    #
    # @return [Hash] Detailed statistics about the registry
    def stats
      base_stats.merge(
        total_namespaces: @namespaces.size,
        total_handlers: count_total_handlers,
        handlers_by_namespace: count_handlers_by_namespace,
        versions_by_namespace: count_versions_by_namespace
      )
    end

    # Get all registered handlers (required by BaseRegistry)
    #
    # @return [Hash] All registered handlers
    def all_items
      @handler_classes.dup
    end

    # Clear all registered handlers (required by BaseRegistry)
    #
    # @return [Boolean] True if cleared successfully
    def clear!
      clear_all!
    end

    # Clear all registered handlers (for testing)
    #
    # @return [Boolean] True if cleared successfully
    def clear_all!
      thread_safe_operation do
        @handler_classes.clear
        @namespaces = Set.new([:default])
        log_registry_operation('cleared_all')
        true
      end
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
      error_msg = "Failed to instantiate handler: #{e.message}"
      log_registry_error('handler_instantiation', e, handler_class: handler_class)
      raise(Tasker::ProceduralError, error_msg)
    end

    # Raise appropriate error for handler not found
    #
    # @param name [String, Symbol] Handler name that was not found
    # @param namespace_name [Symbol] The namespace that was searched
    # @param version [String] The version that was searched
    # @raise [Tasker::ProceduralError] Handler not found error
    def raise_handler_not_found(name, namespace_name, version)
      error_msg = if namespace_name == :default
                    "No task handler for #{name}"
                  else
                    "No task handler for #{name} in namespace #{namespace_name} and version #{version}"
                  end

      log_registry_error('handler_not_found', StandardError.new(error_msg),
                         handler_name: name,
                         namespace_name: namespace_name,
                         version: version)

      raise(Tasker::ProceduralError, error_msg)
    end

    # Count total handlers across all namespaces and versions
    #
    # @return [Integer] Total number of registered handlers
    def count_total_handlers
      @handler_classes.values.sum do |namespace_handlers|
        namespace_handlers.values.sum(&:size)
      end
    end

    # Count handlers by namespace
    #
    # @return [Hash] Namespace => handler count mapping
    def count_handlers_by_namespace
      @handler_classes.transform_values do |namespace_handlers|
        namespace_handlers.values.sum(&:size)
      end
    end

    # Count versions by namespace
    #
    # @return [Hash] Namespace => version count mapping
    def count_versions_by_namespace
      @handler_classes.transform_values do |namespace_handlers|
        namespace_handlers.keys.size
      end
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
