# frozen_string_literal: true

require_relative 'base_subscriber'

module Tasker
  module Events
    module Subscribers
      # MetricsSubscriber bridges events to the EventRouter for automatic metrics collection
      #
      # This subscriber is the critical bridge between Tasker's event publishing system
      # and the EventRouter-based metrics collection. It subscribes to all events that
      # should route to metrics and forwards them to EventRouter.route_event().
      #
      # Architecture:
      # - TelemetrySubscriber: Creates OpenTelemetry spans for debugging
      # - MetricsSubscriber: Routes events to EventRouter for metrics collection
      # - EventRouter: Intelligent routing to MetricsBackend based on configuration
      # - MetricsBackend: Thread-safe native metrics storage
      #
      # This subscriber automatically subscribes to all events configured in EventRouter
      # that route to metrics, ensuring zero-configuration metrics collection.
      class MetricsSubscriber < BaseSubscriber
        def initialize
          super
          @event_router = Tasker::Telemetry::EventRouter.instance

          # Dynamically subscribe to all events that route to metrics
          subscribe_to_metrics_events
        end

        # Handle any event by routing it through EventRouter
        #
        # This is a catch-all handler that routes events to the EventRouter
        # based on the configured mappings.
        #
        # @param event_name [String] The event name
        # @param event [Hash, Dry::Events::Event] The event payload
        # @return [void]
        def handle_event(event_name, event)
          return unless should_process_event?(event_name)

          # Extract payload from event object if needed
          payload = event.respond_to?(:payload) ? event.payload : event

          # Route to EventRouter for intelligent backend routing
          @event_router.route_event(event_name, payload)
        end

        # Override method_missing to handle dynamic event methods
        #
        # Since we subscribe to events dynamically, we need to handle
        # the resulting method calls dynamically as well.
        #
        # @param method_name [Symbol] The method name
        # @param args [Array] Method arguments
        # @return [void]
        def method_missing(method_name, *args)
          if method_name.to_s.start_with?('handle_')
            # Extract event name from method name
            event_name = method_name.to_s.sub(/^handle_/, '').tr('_', '.')
            handle_event(event_name, args.first)
          else
            super
          end
        end

        # Check if we respond to dynamic event handler methods
        #
        # @param method_name [Symbol] The method name
        # @param include_private [Boolean] Whether to include private methods
        # @return [Boolean] True if we respond to the method
        def respond_to_missing?(method_name, include_private = false)
          method_name.to_s.start_with?('handle_') || super
        end

        # Override BaseSubscriber to check EventRouter configuration
        #
        # @param event_constant [String] The event constant or name
        # @return [Boolean] True if the event should be processed
        def should_process_event?(event_constant)
          # Only process if telemetry is enabled
          return false unless Tasker.configuration.telemetry.enabled

          # Convert constant to event name if needed
          event_name = event_constant.respond_to?(:name) ? event_constant.name : event_constant.to_s

          # Check if EventRouter routes this event to metrics
          @event_router.routes_to_metrics?(event_name)
        end

        private

        # Subscribe to all events that route to metrics
        #
        # This method dynamically subscribes to events based on EventRouter configuration
        # @return [void]
        def subscribe_to_metrics_events
          metrics_events = @event_router.events_for_backend(:metrics)

          # Convert event names to constants and subscribe
          event_constants = metrics_events.filter_map do |event_name|
            # Convert dot notation to constant path
            constant_path = event_name.split('.').map(&:upcase).join('::')

            begin
              # Try to resolve the constant
              Tasker::Constants.const_get(constant_path)
            rescue NameError
              # If constant doesn't exist, use the string directly
              event_name
            end
          end

          # Subscribe to the events
          self.class.subscribe_to(*event_constants) unless event_constants.empty?
        end
      end
    end
  end
end
