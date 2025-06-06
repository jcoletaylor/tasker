# frozen_string_literal: true

require_relative 'events/catalog'
require_relative 'events/publisher'
require_relative 'events/subscribers/base_subscriber'

module Tasker
  module Events
    # Delegate catalog methods to the Catalog class for clean developer API
    class << self
      delegate :catalog, :event_info, :task_events, :step_events, :workflow_events,
               :observability_events, :custom_events, :complete_catalog,
               :search_events, :events_by_namespace, :print_catalog, to: :catalog_instance

      # Register a custom event
      #
      # @param name [String] Event name (must contain namespace, e.g., 'order.fulfilled')
      # @param description [String] Human-readable description
      # @param fired_by [Array<String>] Components that fire this event
      # @return [void]
      # @raise [ArgumentError] If event name is invalid or conflicts with system events
      def register_custom_event(name, description: 'Custom event', fired_by: [])
        Tasker::Events::CustomRegistry.instance.register_event(
          name,
          description: description,
          fired_by: fired_by
        )
      end

      private

      def catalog_instance
        @catalog_instance ||= Catalog
      end
    end
  end
end
