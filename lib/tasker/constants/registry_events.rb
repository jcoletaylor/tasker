# typed: false
# frozen_string_literal: true

module Tasker
  module Constants
    # Registry system events
    #
    # Events published by registry systems for registration,
    # unregistration, validation, and coordination activities.
    module RegistryEvents
      # Handler registration events
      HANDLER_REGISTERED = 'handler.registered'
      HANDLER_UNREGISTERED = 'handler.unregistered'
      HANDLER_VALIDATION_FAILED = 'handler.validation_failed'

      # Plugin registration events
      PLUGIN_REGISTERED = 'plugin.registered'
      PLUGIN_UNREGISTERED = 'plugin.unregistered'
      PLUGIN_VALIDATION_FAILED = 'plugin.validation_failed'

      # Subscriber registration events
      SUBSCRIBER_REGISTERED = 'subscriber.registered'
      SUBSCRIBER_UNREGISTERED = 'subscriber.unregistered'
      SUBSCRIBER_VALIDATION_FAILED = 'subscriber.validation_failed'

      # Registry coordination events
      REGISTRY_SYNC_REQUESTED = 'registry.sync_requested'
      REGISTRY_HEALTH_CHECK = 'registry.health_check'
      REGISTRY_STATS_COLLECTED = 'registry.stats_collected'

      # Cross-registry events
      CROSS_REGISTRY_DISCOVERY = 'registry.cross_discovery'
      REGISTRY_COORDINATION_COMPLETE = 'registry.coordination_complete'

      # All registry events for convenient bulk subscription
      ALL_REGISTRY_EVENTS = [
        HANDLER_REGISTERED,
        HANDLER_UNREGISTERED,
        HANDLER_VALIDATION_FAILED,
        PLUGIN_REGISTERED,
        PLUGIN_UNREGISTERED,
        PLUGIN_VALIDATION_FAILED,
        SUBSCRIBER_REGISTERED,
        SUBSCRIBER_UNREGISTERED,
        SUBSCRIBER_VALIDATION_FAILED,
        REGISTRY_SYNC_REQUESTED,
        REGISTRY_HEALTH_CHECK,
        REGISTRY_STATS_COLLECTED,
        CROSS_REGISTRY_DISCOVERY,
        REGISTRY_COORDINATION_COMPLETE
      ].freeze
    end
  end
end
