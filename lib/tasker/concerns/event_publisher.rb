# frozen_string_literal: true

require_relative '../events/event_payload_builder'

module Tasker
  module Concerns
    # EventPublisher provides a clean interface for publishing events
    #
    # This concern eliminates the line noise of repeatedly calling
    # Tasker::Events::Publisher.instance.publish throughout the codebase
    # while maintaining proper error handling and standardized payload creation.
    module EventPublisher
      extend ActiveSupport::Concern

      private

      # Publish an event through the unified Events::Publisher
      #
      # @param event_name [String] The event name/constant
      # @param payload [Hash] The event payload
      # @return [void]
      def publish_event(event_name, payload = {})
        # Add timestamp if not present
        payload[:timestamp] ||= Time.current

        # Publish through the unified publisher
        # If Events::Publisher isn't defined, let it fail fast - that's a real configuration error
        Tasker::Events::Publisher.instance.publish(event_name, payload)
      rescue StandardError => e
        # Trap publishing errors so they don't break core system flow
        # but let configuration errors (missing publisher) bubble up
        Rails.logger.error { "Error publishing event #{event_name}: #{e.message}" }
      end

      # Publish a standardized step event using EventPayloadBuilder
      #
      # @param event_name [String] The event name/constant
      # @param step [WorkflowStep] The step object
      # @param event_type [Symbol] The event type (:started, :completed, :failed, :retry)
      # @param additional_context [Hash] Additional context to merge
      # @return [void]
      def publish_step_event(event_name, step, event_type:, additional_context: {})
        task = step.task
        payload = Tasker::Events::EventPayloadBuilder.build_step_payload(
          step,
          task,
          event_type: event_type,
          additional_context: additional_context
        )

        publish_event(event_name, payload)
      end

      # Publish a standardized task event using EventPayloadBuilder
      #
      # @param event_name [String] The event name/constant
      # @param task [Task] The task object
      # @param event_type [Symbol] The event type (:started, :completed, :failed)
      # @param additional_context [Hash] Additional context to merge
      # @return [void]
      def publish_task_event(event_name, task, event_type:, additional_context: {})
        payload = Tasker::Events::EventPayloadBuilder.build_task_payload(
          task,
          event_type: event_type,
          additional_context: additional_context
        )

        publish_event(event_name, payload)
      end

      # Publish a standardized orchestration event using EventPayloadBuilder
      #
      # @param event_name [String] The event name/constant
      # @param event_type [Symbol] The orchestration event type
      # @param context [Hash] The orchestration context
      # @return [void]
      def publish_orchestration_event(event_name, event_type:, context: {})
        payload = Tasker::Events::EventPayloadBuilder.build_orchestration_payload(
          event_type: event_type,
          context: context
        )

        publish_event(event_name, payload)
      end
    end
  end
end
