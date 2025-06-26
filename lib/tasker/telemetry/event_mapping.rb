# frozen_string_literal: true

module Tasker
  module Telemetry
    # EventMapping represents a single event→telemetry routing configuration
    #
    # This class defines how a specific event should be routed to telemetry backends.
    # It uses dry-struct for immutability and type safety, following the established
    # pattern from Tasker::Types configuration classes.
    #
    # @example Basic event mapping
    #   mapping = EventMapping.new(
    #     event_name: 'task.completed',
    #     backends: [:trace, :metrics],
    #     enabled: true
    #   )
    #
    # @example Metrics-only mapping for operational data
    #   mapping = EventMapping.new(
    #     event_name: 'observability.task.enqueue',
    #     backends: [:metrics],
    #     sampling_rate: 1.0
    #   )
    #
    # @example Trace-only mapping for debugging
    #   mapping = EventMapping.new(
    #     event_name: 'step.before_handle',
    #     backends: [:trace],
    #     sampling_rate: 0.1  # Sample 10% for performance
    #   )
    class EventMapping < Tasker::Types::BaseConfig
      transform_keys(&:to_sym)

      # The event name to route
      #
      # @!attribute [r] event_name
      #   @return [String] Event name in dot notation (e.g., 'task.completed')
      attribute :event_name, Tasker::Types::String

      # Which telemetry backends should receive this event
      #
      # @!attribute [r] backends
      #   @return [Array<Symbol>] List of backend types (:trace, :metrics, :logs)
      attribute :backends, Tasker::Types::Array.of(Tasker::Types::Symbol).default([:trace].freeze)

      # Override initialize to ensure backends array is frozen
      def initialize(*)
        super
        backends.freeze
        # Don't freeze here - BaseConfig already freezes the object
      end

      # Whether this mapping is currently enabled
      #
      # @!attribute [r] enabled
      #   @return [Boolean] True if this mapping should be processed
      attribute :enabled, Tasker::Types::Bool.default(true)

      # Sampling rate for this event (0.0 to 1.0)
      #
      # @!attribute [r] sampling_rate
      #   @return [Float] Sampling rate (1.0 = 100%, 0.1 = 10%)
      attribute :sampling_rate, Tasker::Types::Float.default(1.0)

      # Priority level for this event mapping
      #
      # @!attribute [r] priority
      #   @return [Symbol] Priority level (:low, :normal, :high, :critical)
      attribute :priority, Tasker::Types::Symbol.default(:normal)

      # Additional metadata for this mapping
      #
      # @!attribute [r] metadata
      #   @return [Hash] Additional configuration data
      attribute :metadata, Tasker::Types::Hash.default({}.freeze)

      # Check if this mapping routes to traces
      #
      # @return [Boolean] True if backends includes :trace
      def routes_to_traces?
        backends.include?(:trace)
      end

      # Check if this mapping routes to metrics
      #
      # @return [Boolean] True if backends includes :metrics
      def routes_to_metrics?
        backends.include?(:metrics)
      end

      # Check if this mapping routes to logs
      #
      # @return [Boolean] True if backends includes :logs
      def routes_to_logs?
        backends.include?(:logs)
      end

      # Check if this event should be sampled
      #
      # Uses a simple random sampling approach. For production, you might want
      # to implement more sophisticated sampling strategies.
      #
      # @return [Boolean] True if this event should be processed
      def should_sample?
        return true if sampling_rate >= 1.0
        return false if sampling_rate <= 0.0

        Random.rand <= sampling_rate
      end

      # Check if this mapping is active (enabled and should be sampled)
      #
      # @return [Boolean] True if this mapping should be processed
      def active?
        enabled && should_sample?
      end

      # Get a description of this mapping for debugging
      #
      # @return [String] Human-readable description
      def description
        "#{event_name} → #{backends.join(', ')} (#{(sampling_rate * 100).round(1)}% sampled)"
      end
    end
  end
end
