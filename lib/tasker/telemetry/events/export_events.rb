# frozen_string_literal: true

module Tasker
  module Telemetry
    module Events
      # Export coordination events for plugin architecture
      module ExportEvents
        # Event fired when metrics are synced to cache
        CACHE_SYNCED = 'tasker.telemetry.cache_synced'

        # Event fired when export is requested
        EXPORT_REQUESTED = 'tasker.telemetry.export_requested'

        # Event fired when export is completed
        EXPORT_COMPLETED = 'tasker.telemetry.export_completed'

        # Event fired when export fails
        EXPORT_FAILED = 'tasker.telemetry.export_failed'

        # Event fired when plugin is registered
        PLUGIN_REGISTERED = 'tasker.telemetry.plugin_registered'

        # Event fired when plugin is unregistered
        PLUGIN_UNREGISTERED = 'tasker.telemetry.plugin_unregistered'

        # All export events for easy iteration
        ALL_EVENTS = [
          CACHE_SYNCED,
          EXPORT_REQUESTED,
          EXPORT_COMPLETED,
          EXPORT_FAILED,
          PLUGIN_REGISTERED,
          PLUGIN_UNREGISTERED
        ].freeze
      end
    end
  end
end
