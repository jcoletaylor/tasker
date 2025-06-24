# frozen_string_literal: true

require 'dry/events'
require 'singleton'
require_relative '../concerns/idempotent_state_transitions'

module Tasker
  module Events
    # Core event infrastructure for the Tasker system
    #
    # This publisher provides the core event infrastructure using dry-events.
    # It handles event registration and basic publishing capabilities.
    #
    # Events are now statically defined in constants.rb and registered here.
    # State machine mappings and metadata are loaded from YAML.
    #
    # For application usage, use the EventPublisher concern which provides
    # clean domain-specific methods that build standardized payloads:
    #
    #   include Tasker::Concerns::EventPublisher
    #   publish_step_completed(step, additional_context: {...})
    #   publish_task_failed(task, error_message: "...")
    class Publisher
      # @!visibility private
      include Dry::Events::Publisher[:tasker]
      include Tasker::Concerns::IdempotentStateTransitions
      include Singleton

      def initialize
        # Register all static events from constants
        register_static_events
      end

      # Core publish method with automatic timestamp enhancement
      #
      # This is the primary method used by the EventPublisher concern.
      # Applications should use the EventPublisher concern methods instead
      # of calling this directly.
      #
      # @param event_name [String] The event name
      # @param payload [Hash] The event payload
      # @return [void]
      def publish(event_name, payload = {})
        # Ensure timestamp is always present in the payload
        enhanced_payload = {
          timestamp: Time.current
        }.merge(payload)

        # Call the parent publish method
        super(event_name, enhanced_payload)
      end

      private

      # Register all events from static constants
      #
      # This uses the statically defined constants instead of runtime generation
      def register_static_events
        Rails.logger.info('Tasker: Registering events from static constants')

        event_count = 0

        # Register Task Events
        Tasker::Constants::TaskEvents.constants.each do |const_name|
          event_constant = Tasker::Constants::TaskEvents.const_get(const_name)
          register_event(event_constant)
          event_count += 1
        end

        # Register Step Events
        Tasker::Constants::StepEvents.constants.each do |const_name|
          event_constant = Tasker::Constants::StepEvents.const_get(const_name)
          register_event(event_constant)
          event_count += 1
        end

        # Register Workflow Events
        Tasker::Constants::WorkflowEvents.constants.each do |const_name|
          event_constant = Tasker::Constants::WorkflowEvents.const_get(const_name)
          register_event(event_constant)
          event_count += 1
        end

        # Register Observability Events
        register_observability_events
        event_count += count_observability_events

        # Register Export Events
        register_export_events
        event_count += count_export_events

        # Register Test Events (for testing environments)
        register_test_events
        event_count += count_test_events

        Rails.logger.info("Tasker: Successfully registered #{event_count} events from static constants")
      end

      # Register nested observability events
      def register_observability_events
        # Task observability events
        Tasker::Constants::ObservabilityEvents::Task.constants.each do |const_name|
          event_constant = Tasker::Constants::ObservabilityEvents::Task.const_get(const_name)
          register_event(event_constant)
        end

        # Step observability events
        Tasker::Constants::ObservabilityEvents::Step.constants.each do |const_name|
          event_constant = Tasker::Constants::ObservabilityEvents::Step.const_get(const_name)
          register_event(event_constant)
        end
      end

      # Register export events for telemetry plugin coordination
      def register_export_events
        require_relative '../telemetry/events/export_events'

        Tasker::Telemetry::Events::ExportEvents::ALL_EVENTS.each do |event_name|
          register_event(event_name)
        end
      end

      # Register test events for testing environments
      def register_test_events
        Tasker::Constants::TestEvents.constants.each do |const_name|
          event_constant = Tasker::Constants::TestEvents.const_get(const_name)
          register_event(event_constant)
        end
      end

      # Count observability events for logging
      def count_observability_events
        task_count = Tasker::Constants::ObservabilityEvents::Task.constants.size
        step_count = Tasker::Constants::ObservabilityEvents::Step.constants.size
        task_count + step_count
      end

      # Count export events for logging
      def count_export_events
        Tasker::Telemetry::Events::ExportEvents::ALL_EVENTS.size
      end

      # Count test events for logging
      def count_test_events
        Tasker::Constants::TestEvents.constants.size
      end
    end
  end
end
