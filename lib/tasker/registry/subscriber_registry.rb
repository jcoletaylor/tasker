# typed: false
# frozen_string_literal: true

require_relative 'base_registry'
require_relative 'interface_validator'
require 'concurrent-ruby'

module Tasker
  module Registry
    # Registry for managing event subscribers
    #
    # Provides centralized management of event subscribers with discovery,
    # registration, and event-based lookup capabilities. Integrates with
    # the existing event system to provide comprehensive subscriber coordination.
    #
    # @example Register a subscriber
    #   registry = Tasker::Registry::SubscriberRegistry.instance
    #   registry.register(MySubscriber, events: ['task.created', 'task.completed'])
    #
    # @example Find subscribers for an event
    #   subscribers = registry.subscribers_for_event('task.created')
    #
    # @example Auto-discover subscribers
    #   registry.auto_discover_subscribers
    class SubscriberRegistry < BaseRegistry
      include Singleton

      def initialize
        super
        @subscribers = Concurrent::Hash.new
        @event_mappings = Concurrent::Hash.new
        log_registry_operation('initialized', total_subscribers: 0, total_events: 0)
      end

      # Register an event subscriber
      #
      # @param subscriber_class [Class] The subscriber class to register
      # @param events [Array<String>] Events this subscriber handles
      # @param replace [Boolean] Whether to replace existing subscriber
      # @param options [Hash] Additional registration options
      # @return [Boolean] True if registration successful
      # @raise [ArgumentError] If subscriber already exists and replace is false
      def register(subscriber_class, events: [], replace: false, **options)
        subscriber_name = subscriber_class.name.demodulize.underscore

        thread_safe_operation do
          # Validate subscriber interface
          begin
            Registry::InterfaceValidator.validate_subscriber!(subscriber_class)
          rescue ArgumentError => e
            log_validation_failure('event_subscriber', subscriber_name, e.message)
            raise
          end

          # Check for existing subscriber
          if @subscribers.key?(subscriber_name) && !replace
            raise ArgumentError, "Subscriber '#{subscriber_name}' already registered. Use replace: true to override."
          end

          # Remove existing subscriber if replacing
          if @subscribers.key?(subscriber_name)
            existing_config = @subscribers[subscriber_name]
            unregister_event_mappings(subscriber_name, existing_config[:events])
            log_unregistration('event_subscriber', subscriber_name, existing_config[:subscriber_class])
          end

          # Register subscriber
          subscriber_config = {
            subscriber_class: subscriber_class,
            events: events,
            registered_at: Time.current,
            options: options.merge(replace: replace)
          }

          @subscribers[subscriber_name] = subscriber_config

          # Index by events
          register_event_mappings(subscriber_name, events)

          log_registration('event_subscriber', subscriber_name, subscriber_class,
                          { events: events, event_count: events.size, **options })

          true
        end
      end

      # Unregister an event subscriber
      #
      # @param subscriber_class [Class, String] The subscriber class or name to unregister
      # @return [Boolean] True if unregistered successfully
      def unregister(subscriber_class)
        subscriber_name = if subscriber_class.is_a?(Class)
                            subscriber_class.name.demodulize.underscore
                          else
                            subscriber_class.to_s
                          end

        thread_safe_operation do
          subscriber_config = @subscribers.delete(subscriber_name)

          if subscriber_config
            # Remove from event mappings
            unregister_event_mappings(subscriber_name, subscriber_config[:events])

            log_unregistration('event_subscriber', subscriber_name, subscriber_config[:subscriber_class])
            true
          else
            false
          end
        end
      end

      # Get subscribers for a specific event
      #
      # @param event_name [String] The event name to find subscribers for
      # @return [Array<Hash>] Array of subscriber configurations
      def subscribers_for_event(event_name)
        subscriber_names = @event_mappings[event_name.to_s] || []
        subscriber_names.filter_map { |name| @subscribers[name] }
      end

      # Get all registered subscribers
      #
      # @return [Hash] All registered subscribers
      def all_subscribers
        @subscribers.dup
      end

      # Get all registered subscribers (required by BaseRegistry)
      #
      # @return [Hash] All registered subscribers
      def all_items
        all_subscribers
      end

      # Get supported events across all subscribers
      #
      # @return [Array<String>] Array of supported event names
      def supported_events
        @event_mappings.keys.sort
      end

      # Check if an event has any subscribers
      #
      # @param event_name [String] Event name to check
      # @return [Boolean] True if event has subscribers
      def has_subscribers?(event_name)
        @event_mappings.key?(event_name.to_s) && !@event_mappings[event_name.to_s].empty?
      end

      # Auto-discover subscribers in the subscribers directory
      #
      # @param directory [String] Directory to search for subscribers
      # @return [Integer] Number of subscribers discovered
      def auto_discover_subscribers(directory = nil)
        directory ||= File.join(File.dirname(__FILE__), '..', 'events', 'subscribers')

        return 0 unless Dir.exist?(directory)

        discovered_count = 0

        Dir.glob(File.join(directory, '*_subscriber.rb')).each do |file|
          require file

          # Extract class name from filename
          class_name = File.basename(file, '.rb').camelize
          full_class_name = "Tasker::Events::Subscribers::#{class_name}"

          begin
            # Try to instantiate the subscriber
            subscriber_class = full_class_name.constantize

            # Auto-discover events from class methods or constants
            events = discover_subscriber_events(subscriber_class)

            register(subscriber_class, events: events, auto_discovered: true)
            discovered_count += 1

            log_registry_operation('auto_discovered_subscriber',
                                   subscriber_name: subscriber_class.name,
                                   events: events,
                                   file_path: file)
          rescue StandardError => e
            log_registry_error('auto_discovery_failed', e,
                               file_path: file,
                               class_name: full_class_name)
          end
        end

        discovered_count
      end

      # Get comprehensive registry statistics
      #
      # @return [Hash] Detailed statistics about the registry
      def stats
        base_stats.merge(
          total_subscribers: @subscribers.size,
          total_events: @event_mappings.size,
          events_covered: @event_mappings.keys.sort,
          subscribers_by_event: @event_mappings.transform_values(&:size),
          average_events_per_subscriber: calculate_average_events_per_subscriber,
          most_popular_events: find_most_popular_events
        )
      end

      # Clear all registered subscribers (required by BaseRegistry)
      #
      # @return [Boolean] True if cleared successfully
      def clear!
        thread_safe_operation do
          @subscribers.clear
          @event_mappings.clear
          log_registry_operation('cleared_all')
          true
        end
      end

      private

      # Register event mappings for a subscriber
      #
      # @param subscriber_name [String] Name of the subscriber
      # @param events [Array<String>] Events to map
      def register_event_mappings(subscriber_name, events)
        events.each do |event|
          event_key = event.to_s
          @event_mappings[event_key] ||= []
          @event_mappings[event_key] << subscriber_name unless @event_mappings[event_key].include?(subscriber_name)
        end
      end

      # Unregister event mappings for a subscriber
      #
      # @param subscriber_name [String] Name of the subscriber
      # @param events [Array<String>] Events to unmap
      def unregister_event_mappings(subscriber_name, events)
        events.each do |event|
          event_key = event.to_s
          @event_mappings[event_key]&.delete(subscriber_name)
          @event_mappings.delete(event_key) if @event_mappings[event_key] && @event_mappings[event_key].empty?
        end
      end

      # Discover events that a subscriber handles
      #
      # @param subscriber_class [Class] The subscriber class to analyze
      # @return [Array<String>] Array of event names
      def discover_subscriber_events(subscriber_class)
        events = []

        # Check for EVENTS constant
        if subscriber_class.const_defined?(:EVENTS)
          events.concat(Array(subscriber_class::EVENTS))
        end

        # Check for events class method
        if subscriber_class.respond_to?(:events)
          events.concat(Array(subscriber_class.events))
        end

        # Check for event_patterns class method
        if subscriber_class.respond_to?(:event_patterns)
          events.concat(Array(subscriber_class.event_patterns))
        end

        events.map(&:to_s).uniq
      end

      # Calculate average events per subscriber
      #
      # @return [Float] Average number of events per subscriber
      def calculate_average_events_per_subscriber
        return 0.0 if @subscribers.empty?

        total_events = @subscribers.values.sum { |config| config[:events].size }
        (total_events.to_f / @subscribers.size).round(2)
      end

      # Find the most popular events (top 5)
      #
      # @return [Array<Hash>] Array of event popularity data
      def find_most_popular_events
        @event_mappings
          .map { |event, subscribers| { event: event, subscriber_count: subscribers.size } }
          .sort_by { |data| -data[:subscriber_count] }
          .first(5)
      end
    end
  end
end
