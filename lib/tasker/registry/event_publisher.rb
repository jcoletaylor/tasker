# typed: false
# frozen_string_literal: true

require_relative '../concerns/event_publisher'

module Tasker
  module Registry
    # Event publishing capabilities for registry systems
    #
    # Provides standardized event publishing for registration,
    # unregistration, and validation events across all registries.
    module EventPublisher
      extend ActiveSupport::Concern

      included do
        include Tasker::Concerns::EventPublisher
      end

      # Publish registration event
      #
      # @param entity_type [String] Type of entity being registered
      # @param entity_id [String] Unique identifier for the entity
      # @param entity_class [Class, String] Class of the entity being registered
      # @param options [Hash] Additional registration options
      def publish_registration_event(entity_type, entity_id, entity_class, options = {})
        event_name = "#{entity_type}.registered"
        class_name = entity_class.is_a?(Class) ? entity_class.name : entity_class.to_s

        publish_event(event_name, {
                        registry_name: @registry_name,
                        entity_type: entity_type,
                        entity_id: entity_id,
                        entity_class: class_name,
                        options: options,
                        registered_at: Time.current,
                        correlation_id: correlation_id
                      })
      end

      # Publish unregistration event
      #
      # @param entity_type [String] Type of entity being unregistered
      # @param entity_id [String] Unique identifier for the entity
      # @param entity_class [Class, String] Class of the entity being unregistered
      def publish_unregistration_event(entity_type, entity_id, entity_class)
        event_name = "#{entity_type}.unregistered"
        class_name = entity_class.is_a?(Class) ? entity_class.name : entity_class.to_s

        publish_event(event_name, {
                        registry_name: @registry_name,
                        entity_type: entity_type,
                        entity_id: entity_id,
                        entity_class: class_name,
                        unregistered_at: Time.current,
                        correlation_id: correlation_id
                      })
      end

      # Publish validation failure event
      #
      # @param entity_type [String] Type of entity that failed validation
      # @param entity_class [Class, String] Class of the entity that failed validation
      # @param error [StandardError] The validation error that occurred
      def publish_validation_failed_event(entity_type, entity_class, error)
        event_name = "#{entity_type}.validation_failed"
        class_name = entity_class.is_a?(Class) ? entity_class.name : entity_class.to_s

        publish_event(event_name, {
                        registry_name: @registry_name,
                        entity_type: entity_type,
                        entity_class: class_name,
                        validation_error: error.message,
                        failed_at: Time.current,
                        correlation_id: correlation_id
                      })
      end

      # Publish registry statistics collection event
      #
      # @param stats [Hash] Registry statistics
      def publish_registry_stats_event(stats)
        publish_event('registry.stats_collected', {
                        registry_name: @registry_name,
                        stats: stats,
                        collected_at: Time.current,
                        correlation_id: correlation_id
                      })
      end
    end
  end
end
