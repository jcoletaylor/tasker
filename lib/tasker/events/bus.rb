# frozen_string_literal: true

require 'dry/events'
require_relative 'publisher'

module Tasker
  module Events
    # Simplified event bus following dry-events best practices
    #
    # This bus coordinates event publishing and subscription throughout
    # the Tasker system using dry-events primitives.
    class Bus
      include Singleton

      def initialize
        @publisher = Publisher.new
        @subscribers = []
      end

      # Get the publisher instance
      #
      # @return [Publisher] The event publisher
      attr_reader :publisher

      # Subscribe a callable to an event
      #
      # @param event_name [String] The event to subscribe to
      # @param callable [Proc, Method] The callback
      def subscribe(event_name, callable = nil, &block)
        handler = callable || block
        @publisher.subscribe(event_name, &handler)
        @subscribers << { event: event_name, handler: handler }
      end

      # Subscribe an object that responds to event methods
      #
      # @param subscriber [Object] Object with event handling methods
      def subscribe_object(subscriber)
        subscriber_class = subscriber.class

        if subscriber_class.respond_to?(:subscribe)
          subscriber_class.subscribe(@publisher)
        else
          Rails.logger.warn("Subscriber #{subscriber_class} does not implement .subscribe method")
        end
      end

      # Publish an event through the bus
      #
      # @param event_name [String] The event name
      # @param payload [Hash] The event payload
      def publish(event_name, payload = {})
        @publisher.publish(event_name, payload)
      end

      # Publish a task event with standard payload
      #
      # @param event_name [String] The event name
      # @param task [Object] The task object
      # @param metadata [Hash] Additional metadata
      def publish_task_event(event_name, task, metadata = {})
        @publisher.publish_task_event(event_name, task, metadata)
      end

      # Publish a step event with standard payload
      #
      # @param event_name [String] The event name
      # @param step [Object] The step object
      # @param metadata [Hash] Additional metadata
      def publish_step_event(event_name, step, metadata = {})
        @publisher.publish_step_event(event_name, step, metadata)
      end

      # Publish a workflow event with minimal payload
      #
      # @param event_name [String] The event name
      # @param context [Hash] The event context
      def publish_workflow_event(event_name, context = {})
        @publisher.publish_workflow_event(event_name, context)
      end

      # Get list of registered subscribers
      #
      # @return [Array] List of subscriber info
      def subscribers
        @subscribers.dup
      end

      # Initialize default subscribers
      def setup_default_subscribers
        # Auto-load and subscribe telemetry subscriber
        return unless defined?(Tasker::Events::Subscribers::TelemetrySubscriber)

        subscribe_object(Tasker::Events::Subscribers::TelemetrySubscriber)
      end

      # Class methods for global access
      class << self
        # Get the global event bus instance
        #
        # @return [Bus] The singleton bus instance
        def instance
          @instance ||= new
        end

        # Delegate common methods to the singleton
        delegate :publish, :subscribe, :subscribe_object,
                 :publish_task_event, :publish_step_event, :publish_workflow_event,
                 to: :instance
      end
    end
  end
end
