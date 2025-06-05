# frozen_string_literal: true

require_relative 'events/catalog'
require_relative 'events/publisher'
require_relative 'events/subscribers/base_subscriber'

module Tasker
  module Events
    # Delegate catalog methods to the Catalog class for clean developer API
    class << self
      delegate :catalog, :event_info, :task_events, :step_events, :workflow_events,
               :observability_events, :custom_events, :print_catalog, to: :catalog_instance

      private

      def catalog_instance
        @catalog_instance ||= Catalog
      end
    end
  end
end
