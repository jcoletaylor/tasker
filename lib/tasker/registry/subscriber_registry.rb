# typed: false
# frozen_string_literal: true

module Tasker
  module Registry
    # Centralized registry for event subscribers
    #
    # Provides thread-safe management of event subscribers with
    # discovery capabilities, statistics, and health monitoring.
    class SubscriberRegistry < BaseRegistry
      include Singleton
      include EventPublisher

      def initialize
        super
        @subscribers = Concurrent::Hash.new
        @event_mappings = Concurrent::Hash.new
      end

      # Register an event subscriber
      #
      # @param subscriber_class [Class] Subscriber class to register
      # @param events [Array<String>] Events this subscriber handles
      # @param options [Hash] Additional registration options
      # @return [Boolean] True if registration successful
      # @raise [ArgumentError] If validation fails
      def register(subscriber_class, events: [], options: {})
        subscriber_name = subscriber_class.name.demodulize.underscore

        thread_safe_operation do
          # Validate subscriber interface
          Registry::InterfaceValidator.validate_subscriber!(subscriber_class)

          # Validate registration parameters
          validate_registration_params!(subscriber_name, subscriber_class, options)

          # Register subscriber
          subscriber_config = create_subscriber_config(subscriber_class, events, options)
          @subscribers[subscriber_name] = subscriber_config

          # Index by events for fast lookup
          events.each do |event|
            @event_mappings[event] ||= Set.new
            @event_mappings[event] << subscriber_name
          end

          # Log and publish registration
          log_registration('subscriber', subscriber_name, subscriber_class,
                           { events: events }.merge(options))
          publish_registration_event('subscriber', subscriber_name, subscriber_class,
                                     { events: events }.merge(options))

          true
        end
      rescue ArgumentError => e
        publish_validation_failed_event('subscriber', subscriber_class, e)
        raise
      end

      # Find subscribers for a specific event
      #
      # @param event_name [String] Event name to find subscribers for
      # @return [Array<Hash>] Array of subscriber configurations
      def subscribers_for_event(event_name)
        subscriber_names = @event_mappings[event_name] || Set.new
        subscriber_names.filter_map { |name| @subscribers[name] }
      end

      # Find subscribers matching criteria
      #
      # @param criteria [Hash] Search criteria
      # @option criteria [String] :event Filter by event name
      # @option criteria [Regexp] :name_pattern Filter by subscriber name pattern
      # @option criteria [String] :class_pattern Filter by class name pattern
      # @return [Hash] Matching subscribers
      def find_subscribers(criteria = {})
        result = @subscribers.dup

        if criteria[:event]
          event_subscribers = subscribers_for_event(criteria[:event])
          subscriber_names = event_subscribers.pluck(:name)
          result = result.slice(*subscriber_names)
        end

        if criteria[:name_pattern]
          pattern = if criteria[:name_pattern].is_a?(Regexp)
                      criteria[:name_pattern]
                    else
                      Regexp.new(
                        criteria[:name_pattern], Regexp::IGNORECASE
                      )
                    end
          result = result.select { |name, _| name.match?(pattern) }
        end

        if criteria[:class_pattern]
          pattern = if criteria[:class_pattern].is_a?(Regexp)
                      criteria[:class_pattern]
                    else
                      Regexp.new(
                        criteria[:class_pattern], Regexp::IGNORECASE
                      )
                    end
          result = result.select { |_, config| config[:subscriber_class].name.match?(pattern) }
        end

        result
      end

      # Unregister a subscriber
      #
      # @param subscriber_name [String] Name of subscriber to unregister
      # @return [Boolean] True if subscriber was removed
      def unregister(subscriber_name)
        thread_safe_operation do
          subscriber_config = @subscribers.delete(subscriber_name)
          return false unless subscriber_config

          # Remove from event mappings
          subscriber_config[:events].each do |event|
            @event_mappings[event]&.delete(subscriber_name)
            @event_mappings.delete(event) if @event_mappings[event] && @event_mappings[event].empty?
          end

          # Log and publish unregistration
          log_unregistration('subscriber', subscriber_name, subscriber_config[:subscriber_class])
          publish_unregistration_event('subscriber', subscriber_name, subscriber_config[:subscriber_class])

          true
        end
      end

      # Check if subscriber is registered
      #
      # @param subscriber_name [String] Subscriber name to check
      # @return [Boolean] True if subscriber is registered
      def registered?(subscriber_name)
        @subscribers.key?(subscriber_name)
      end

      # Get all events covered by registered subscribers
      #
      # @return [Array<String>] Sorted array of event names
      def covered_events
        @event_mappings.keys.sort
      end

      # Implementation of BaseRegistry interface

      # Get comprehensive statistics for the subscriber registry
      #
      # @return [Hash] Registry statistics
      def stats
        base_stats.merge({
                           total_subscribers: @subscribers.size,
                           total_event_mappings: @event_mappings.size,
                           events_covered: covered_events,
                           subscribers_by_event: calculate_subscribers_by_event,
                           subscriber_distribution: calculate_subscriber_distribution
                         })
      end

      # Get all registered subscribers
      #
      # @return [Hash] All registered subscribers
      def all_items
        @subscribers.dup
      end

      # Clear all subscribers from the registry
      #
      # @return [void]
      def clear!
        thread_safe_operation do
          @subscribers.clear
          @event_mappings.clear
          log_registry_operation('cleared')
        end
      end

      private

      # Create subscriber configuration hash
      #
      # @param subscriber_class [Class] The subscriber class
      # @param events [Array<String>] Events handled by subscriber
      # @param options [Hash] Additional options
      # @return [Hash] Subscriber configuration
      def create_subscriber_config(subscriber_class, events, options)
        {
          name: subscriber_class.name.demodulize.underscore,
          subscriber_class: subscriber_class,
          events: events.dup.freeze,
          registered_at: Time.current,
          options: options.dup.freeze
        }
      end

      # Calculate subscriber count per event
      #
      # @return [Hash] Event names to subscriber counts
      def calculate_subscribers_by_event
        @event_mappings.transform_values(&:size)
      end

      # Calculate distribution statistics for subscribers
      #
      # @return [Hash] Distribution statistics
      def calculate_subscriber_distribution
        events_per_subscriber = @subscribers.values.map { |config| config[:events].size }

        return { distribution: 'empty' } if events_per_subscriber.empty?

        {
          distribution: calculate_distribution_type(events_per_subscriber),
          average_events_per_subscriber: events_per_subscriber.sum.to_f / events_per_subscriber.size,
          max_events_per_subscriber: events_per_subscriber.max,
          min_events_per_subscriber: events_per_subscriber.min
        }
      end

      # Calculate distribution type based on events per subscriber
      #
      # @param events_per_subscriber [Array<Integer>] Array of event counts
      # @return [String] Distribution type
      def calculate_distribution_type(events_per_subscriber)
        return 'empty' if events_per_subscriber.empty?
        return 'uniform' if events_per_subscriber.uniq.size == 1

        avg = events_per_subscriber.sum.to_f / events_per_subscriber.size
        variance = events_per_subscriber.sum { |count| (count - avg)**2 } / events_per_subscriber.size

        variance < 2 ? 'even' : 'varied'
      end
    end
  end
end
