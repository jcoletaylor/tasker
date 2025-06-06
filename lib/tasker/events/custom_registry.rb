# frozen_string_literal: true

require 'singleton'

module Tasker
  module Events
    # CustomRegistry manages registration and validation of developer-defined custom events
    #
    # This registry provides a safe way for developers to define their own events
    # alongside Tasker's system events, with conflict prevention and namespace validation.
    #
    # Usage:
    #   registry = Tasker::Events::CustomRegistry.instance
    #   registry.register_event('order.fulfilled', description: 'Order completed', fired_by: ['OrderService'])
    #
    # Or through the Events module:
    #   Tasker::Events.register_custom_event('order.fulfilled', description: 'Order completed')
    class CustomRegistry
      include Singleton

      def initialize
        @custom_events = {}
      end

      # Register a custom event with metadata
      #
      # @param name [String] Event name (must contain namespace, e.g., 'order.fulfilled')
      # @param description [String] Human-readable description
      # @param fired_by [Array<String>] Components that fire this event
      # @return [void]
      # @raise [ArgumentError] If event name is invalid or conflicts with system events
      def register_event(name, description: 'Custom event', fired_by: [])
        validate_event_name!(name)

        @custom_events[name] = {
          name: name,
          category: 'custom',
          description: description,
          fired_by: Array(fired_by),
          registered_at: Time.current
        }

        # Register with dry-events publisher so subscribers can listen
        Tasker::Events::Publisher.instance.register_event(name)

        Rails.logger.debug { "Registered custom event: #{name}" }
      end

      # Get all registered custom events
      #
      # @return [Hash] Custom events with metadata
      def custom_events
        @custom_events.dup
      end

      # Check if an event is registered as a custom event
      #
      # @param name [String] Event name
      # @return [Boolean] Whether the event is registered
      def registered?(name)
        @custom_events.key?(name)
      end

      # Get metadata for a specific custom event
      #
      # @param name [String] Event name
      # @return [Hash, nil] Event metadata or nil if not found
      def event_metadata(name)
        @custom_events[name]
      end

      # Clear all registered custom events (useful for testing)
      #
      # @return [void]
      def clear!
        @custom_events.clear
      end

      # Alias for clear! to match test expectations
      alias clear_all_events clear!

      # Get all registered custom event names
      #
      # @return [Array<String>] Array of registered event names
      def registered_events
        @custom_events.keys
      end

      # Get event information by name
      #
      # @param name [String] Event name
      # @return [Hash, nil] Event information or nil if not found
      def event_info(name)
        @custom_events[name]
      end

      private

      # Validate event name to prevent conflicts and ensure proper namespacing
      #
      # @param name [String] Event name to validate
      # @raise [ArgumentError] If name is invalid
      def validate_event_name!(name)
        # Ensure the name is a string
        raise ArgumentError, "Event name must be a string, got #{name.class}" unless name.is_a?(String)

        # Ensure namespacing (must contain a dot)
        unless name.include?('.')
          raise ArgumentError, "Custom event name must contain a namespace (e.g., 'order.fulfilled')"
        end

        # Prevent conflicts with system events
        system_events = all_system_event_constants
        raise ArgumentError, "Event name '#{name}' conflicts with system event" if system_events.include?(name)

        # Prevent reserved namespaces
        reserved_namespaces = %w[task step workflow observability test]
        namespace = name.split('.').first.downcase
        if reserved_namespaces.include?(namespace)
          raise ArgumentError, "Namespace '#{namespace}' is reserved for system events"
        end

        # Prevent duplicate registration
        return unless @custom_events.key?(name)

        Rails.logger.warn "Custom event '#{name}' is already registered, skipping"
        nil
      end

      # Get all system event constants to check for conflicts
      #
      # @return [Array<String>] All system event constant values
      def all_system_event_constants
        constants = []

        # Task events
        constants.concat(
          Tasker::Constants::TaskEvents.constants.map do |c|
            Tasker::Constants::TaskEvents.const_get(c)
          end
        )

        # Step events
        constants.concat(
          Tasker::Constants::StepEvents.constants.map do |c|
            Tasker::Constants::StepEvents.const_get(c)
          end
        )

        # Workflow events
        constants.concat(
          Tasker::Constants::WorkflowEvents.constants.map do |c|
            Tasker::Constants::WorkflowEvents.const_get(c)
          end
        )

        # Observability events - Task
        constants.concat(
          Tasker::Constants::ObservabilityEvents::Task.constants.map do |c|
            Tasker::Constants::ObservabilityEvents::Task.const_get(c)
          end
        )

        # Observability events - Step
        constants.concat(
          Tasker::Constants::ObservabilityEvents::Step.constants.map do |c|
            Tasker::Constants::ObservabilityEvents::Step.const_get(c)
          end
        )

        constants
      end
    end
  end
end
