# typed: false
# frozen_string_literal: true

module Tasker
  # Factory for creating task handler instances
  #
  # This class maintains a registry of task handlers by name and
  # provides methods to retrieve handler instances when needed.
  # It follows the Singleton pattern to ensure a single registry.
  class HandlerFactory
    include Singleton

    # @return [Hash] Registered handler class names by handler name
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
      raise(Tasker::ProceduralError, "No task handler for #{name}") unless handler_classes[name.to_sym]

      handler_classes[name.to_sym].to_s.camelize.constantize.new
    end

    # Register a task handler class with a name
    #
    # @param name [String, Symbol] The name to register the handler under
    # @param class_name [Class, String] The handler class to register
    # @return [void]
    def register(name, class_name)
      self.handler_classes[name.to_sym] = class_name.to_s
    end
  end
end
