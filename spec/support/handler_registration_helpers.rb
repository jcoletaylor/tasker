# typed: false
# frozen_string_literal: true

# Helper module for safe handler registration in tests
#
# This module provides utilities for registering handlers in tests without
# causing duplicate registration errors. It's designed to work with the
# modernized HandlerFactory that enforces unique registrations.
module HandlerRegistrationHelpers
  # Register a handler, using replace: true if it already exists
  #
  # @param name [String, Symbol] Handler name
  # @param handler_class [Class, String] Handler class
  # @param options [Hash] Registration options
  # @return [void]
  def safe_register_handler(name, handler_class, **options)
    # Skip registration for auto-registering handlers unless explicitly forced
    if auto_registering_handler?(name) && !options[:force]
      Rails.logger.debug { "Skipping registration of auto-registering handler: #{name}" }
      return
    end

    factory = Tasker::HandlerFactory.instance
    namespace_name = options[:namespace_name] || :default
    version = options[:version] || '0.1.0'

    # Check if handler already exists
    if handler_exists?(name, namespace_name, version)
      # Use replace: true to allow override
      factory.register(name, handler_class, replace: true, **options)
    else
      # Normal registration
      factory.register(name, handler_class, **options)
    end
  end

  # Check if a handler is already registered
  #
  # @param name [String, Symbol] Handler name
  # @param namespace_name [Symbol] Namespace name
  # @param version [String] Version
  # @return [Boolean] True if handler exists
  def handler_exists?(name, namespace_name = :default, version = '0.1.0')
    factory = Tasker::HandlerFactory.instance
    namespace_name = namespace_name.to_sym
    name_sym = name.to_sym

    factory.handler_classes.dig(namespace_name, name_sym, version).present?
  end

  # Register multiple handlers safely
  #
  # @param handlers [Hash] Hash of name => handler_class pairs
  # @param options [Hash] Common options for all registrations
  # @return [void]
  def safe_register_handlers(handlers, **options)
    handlers.each do |name, handler_class|
      safe_register_handler(name, handler_class, **options)
    end
  end

  # Register the common workflow task handlers used in tests
  #
  # @param options [Hash] Registration options
  # @return [void]
  def register_workflow_test_handlers(**)
    workflow_handlers = {
      'linear_workflow_task' => LinearWorkflowTask,
      'diamond_workflow_task' => DiamondWorkflowTask,
      'parallel_merge_workflow_task' => ParallelMergeWorkflowTask,
      'tree_workflow_task' => TreeWorkflowTask,
      'mixed_workflow_task' => MixedWorkflowTask
    }

    safe_register_handlers(workflow_handlers, **)
  end

  # Register the common test task handlers
  #
  # @param options [Hash] Registration options
  # @return [void]
  def register_basic_test_handlers(**)
    basic_handlers = {
      'dummy_task' => DummyTask,
      'dummy_api_task' => DummyApiTask,
      'configurable_failure_task' => ConfigurableFailureTask
    }

    safe_register_handlers(basic_handlers, **)
  end

  # Override factory.register method calls to use safe registration
  #
  # This method can be used to wrap existing test registration patterns
  #
  # @param factory [Object] Handler factory instance
  # @param name [String, Symbol] Handler name
  # @param handler_class [Class, String] Handler class
  # @param options [Hash] Registration options
  # @return [void]
  def safe_factory_register(_factory, name, handler_class, **)
    safe_register_handler(name, handler_class, **)
  end

  # Unregister handlers that were registered during test
  #
  # @param handler_names [Array<String>] Names of handlers to unregister
  # @param options [Hash] Unregistration options
  # @return [void]
  def unregister_test_handlers(handler_names, **options)
    factory = Tasker::HandlerFactory.instance
    namespace_name = (options[:namespace_name] || :default).to_sym
    version = options[:version] || '0.1.0'

    handler_names.each do |name|
      name_sym = name.to_sym
      factory.handler_classes[namespace_name]&.dig(name_sym)&.delete(version)
    end
  end
end

# Auto-registering handlers that should not be registered again in tests
AUTO_REGISTERING_HANDLERS = %w[
  dummy_task
  dummy_api_task
  configurable_failure_task
  linear_workflow_task
  diamond_workflow_task
  parallel_merge_workflow_task
  tree_workflow_task
  mixed_workflow_task
].freeze

# Check if a handler auto-registers itself
#
# @param name [String, Symbol] Handler name
# @return [Boolean] True if handler auto-registers
def auto_registering_handler?(name)
  AUTO_REGISTERING_HANDLERS.include?(name.to_s)
end

# Include in RSpec configuration
RSpec.configure do |config|
  config.include HandlerRegistrationHelpers
end
