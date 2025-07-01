# frozen_string_literal: true

require_relative 'metrics_backend'

module Tasker
  module Telemetry
    # EventRouter provides intelligent routing of events to appropriate telemetry backends
    #
    # This is the strategic core of Phase 4.2.1, enabling declarative event→telemetry mapping
    # while preserving all existing TelemetrySubscriber functionality. It follows the singleton
    # pattern established by HandlerFactory and Events::Publisher.
    #
    # Core Philosophy: PRESERVE all existing 8 TelemetrySubscriber events while adding
    # intelligent routing for 35+ additional lifecycle events.
    #
    # @example Basic configuration
    #   Tasker::Telemetry::EventRouter.configure do |router|
    #     # PRESERVE: All current 8 events → both traces AND metrics
    #     router.map 'task.completed' => [:trace, :metrics]
    #     router.map 'step.failed' => [:trace, :metrics]
    #
    #     # ENHANCE: Add missing lifecycle events with intelligent routing
    #     router.map 'workflow.viable_steps_discovered' => [:trace, :metrics]
    #     router.map 'observability.task.enqueue' => [:metrics]  # Job queue metrics only
    #     router.map 'step.before_handle' => [:trace]            # Handler execution spans
    #   end
    #
    # @example Production sampling configuration
    #   router.map 'step.before_handle' => [:trace], sampling_rate: 0.1  # 10% sampling
    #   router.map 'database.query_executed' => [:trace, :metrics], priority: :high
    #
    class EventRouter
      include Singleton

      # @return [Hash<String, EventMapping>] Registry of event mappings by event name
      attr_reader :mappings

      # @return [Array<String>] List of events that route to traces
      attr_reader :trace_events

      # @return [Array<String>] List of events that route to metrics
      attr_reader :metrics_events

      # @return [Array<String>] List of events that route to logs
      attr_reader :log_events

      # Initialize the event router with default mappings
      def initialize
        @mappings = {}
        @trace_events = []
        @metrics_events = []
        @log_events = []

        # Load default mappings that preserve existing TelemetrySubscriber functionality
        load_default_mappings

        # Register this router with MetricsBackend for automatic routing
        MetricsBackend.instance.register_event_router(self)
      end

      # Configure event routing with a block
      #
      # @yield [EventRouter] The router instance for configuration
      # @return [EventRouter] The configured router instance
      def self.configure
        instance.tap { |router| yield(router) if block_given? }
      end

      # Map an event to specific telemetry backends
      #
      # @param event_name [String, Hash] Event name in dot notation, or hash with event => backends
      # @param backends [Array<Symbol>] List of backend types (:trace, :metrics, :logs)
      # @param options [Hash] Additional mapping options
      # @option options [Boolean] :enabled Whether this mapping is enabled
      # @option options [Float] :sampling_rate Sampling rate (0.0 to 1.0)
      # @option options [Symbol] :priority Priority level (:low, :normal, :high, :critical)
      # @option options [Hash] :metadata Additional metadata
      # @return [EventMapping] The created mapping
      def map(event_name_or_hash, backends: [:trace], **)
        # Handle hash syntax: map 'event' => [:trace, :metrics]
        if event_name_or_hash.is_a?(Hash)
          # Extract the first (and typically only) hash pair
          event_name, extracted_backends = event_name_or_hash.first
          backends = Array(extracted_backends)
        else
          event_name = event_name_or_hash
        end

        # Ensure we always have an event_name
        raise ArgumentError, 'event_name cannot be nil' if event_name.nil?

        mapping = EventMapping.new(
          event_name: event_name.to_s,
          backends: Array(backends),
          **
        )

        register_mapping(mapping)
        mapping
      end

      # Get the mapping for a specific event
      #
      # @param event_name [String] Event name
      # @return [EventMapping, nil] The mapping or nil if not found
      def mapping_for(event_name)
        mappings[event_name.to_s]
      end

      # Check if a mapping exists for a specific event
      #
      # @param event_name [String] Event name
      # @return [Boolean] True if mapping exists
      def mapping_exists?(event_name)
        mappings.key?(event_name.to_s)
      end

      # Check if an event routes to traces
      #
      # @param event_name [String] Event name
      # @return [Boolean] True if the event routes to traces
      def routes_to_traces?(event_name)
        mapping = mapping_for(event_name)
        return false unless mapping

        mapping.active? && mapping.routes_to_traces?
      end

      # Check if an event routes to metrics
      #
      # @param event_name [String] Event name
      # @return [Boolean] True if the event routes to metrics
      def routes_to_metrics?(event_name)
        mapping = mapping_for(event_name)
        return false unless mapping

        mapping.active? && mapping.routes_to_metrics?
      end

      # Check if an event routes to logs
      #
      # @param event_name [String] Event name
      # @return [Boolean] True if the event routes to logs
      def routes_to_logs?(event_name)
        mapping = mapping_for(event_name)
        return false unless mapping

        mapping.active? && mapping.routes_to_logs?
      end

      # Get all events that should route to a specific backend
      #
      # @param backend [Symbol] Backend type (:trace, :metrics, :logs)
      # @return [Array<String>] List of event names
      # @raise [ArgumentError] If backend type is not recognized
      def events_for_backend(backend)
        case backend
        when :trace, :traces
          trace_events
        when :metric, :metrics
          metrics_events
        when :log, :logs
          log_events
        else
          raise ArgumentError, "Unknown backend type: #{backend.inspect}. Valid backends: :trace, :metrics, :logs"
        end
      end

      # Get routing statistics for debugging
      #
      # @return [Hash] Statistics about current routing configuration
      def routing_stats
        {
          total_mappings: mappings.size,
          trace_events: trace_events.size,
          metrics_events: metrics_events.size,
          log_events: log_events.size,
          enabled_mappings: mappings.values.count(&:enabled),
          high_priority: mappings.values.count { |m| m.priority == :high },
          sampled_mappings: mappings.values.count { |m| m.sampling_rate < 1.0 }
        }
      end

      # Reset all mappings (primarily for testing)
      #
      # @return [void]
      def reset!
        @mappings.clear
        @trace_events.clear
        @metrics_events.clear
        @log_events.clear
        load_default_mappings
      end

      # Get a list of all configured event names
      #
      # @return [Array<String>] All configured event names
      def configured_events
        mappings.keys
      end

      # Route an event to appropriate backends based on configuration
      #
      # This is the core routing method that directs events to traces,
      # metrics, and logs based on their configured mapping.
      #
      # @param event_name [String] The lifecycle event name
      # @param payload [Hash] Event payload data
      # @return [Hash] Results from each backend (backend => success boolean)
      def route_event(event_name, payload = {})
        results = {}
        mapping = mapping_for(event_name)
        return results unless mapping&.active?

        # Route to metrics backend if configured
        results[:metrics] = MetricsBackend.instance.handle_event(event_name, payload) if mapping.routes_to_metrics?

        # Route to trace backend if configured
        results[:traces] = TraceBackend.instance.handle_event(event_name, payload) if mapping.routes_to_traces?

        # Route to log backend if configured
        results[:logs] = LogBackend.instance.handle_event(event_name, payload) if mapping.routes_to_logs?

        results
      end

      # Bulk configure multiple mappings
      #
      # @param mappings_config [Hash] Hash of event_name => backend_config
      # @return [Array<EventMapping>] Array of created mappings
      # @raise [ArgumentError] If any mapping configuration is invalid
      def bulk_configure(mappings_config)
        return [] if mappings_config.blank?

        mappings_config.map do |event_name, config|
          if config.is_a?(Array)
            map(event_name, backends: config)
          elsif config.is_a?(Hash)
            map(event_name, **config)
          elsif config.respond_to?(:to_sym)
            map(event_name, backends: [config])
          else
            raise ArgumentError, "Invalid config for #{event_name}: #{config.inspect}. Must be Array, Hash, or Symbol"
          end
        end
      end

      private

      # Register a mapping and update the backend event lists
      #
      # @param mapping [EventMapping] The mapping to register
      # @return [void]
      def register_mapping(mapping)
        @mappings[mapping.event_name] = mapping

        # Update backend-specific event lists
        @trace_events << mapping.event_name if mapping.routes_to_traces? && @trace_events.exclude?(mapping.event_name)

        if mapping.routes_to_metrics? && @metrics_events.exclude?(mapping.event_name)
          @metrics_events << mapping.event_name
        end

        return unless mapping.routes_to_logs?

        @log_events << mapping.event_name unless @log_events.include?(mapping.event_name)
      end

      # Load default mappings that preserve existing TelemetrySubscriber functionality
      #
      # This ensures ZERO BREAKING CHANGES by mapping all current 8 events to both
      # traces and metrics, exactly as they currently work in production.
      #
      # @return [void]
      def load_default_mappings
        # PRESERVE: All current 8 TelemetrySubscriber events → both traces AND metrics
        # This ensures zero breaking changes while enabling intelligent routing

        # Task Events (4 current events)
        map('task.initialize_requested', backends: %i[trace metrics])
        map('task.start_requested', backends: %i[trace metrics])
        map('task.completed', backends: %i[trace metrics])
        map('task.failed', backends: %i[trace metrics])

        # Step Events (4 current events)
        map('step.execution_requested', backends: %i[trace metrics])
        map('step.completed', backends: %i[trace metrics])
        map('step.failed', backends: %i[trace metrics])
        map('step.retry_requested', backends: %i[trace metrics])

        # ENHANCE: Add missing lifecycle events with intelligent routing
        # These are NEW events that weren't covered by the original TelemetrySubscriber

        # Workflow Orchestration Events
        map('workflow.viable_steps_discovered', backends: %i[trace metrics])

        # Observability Events - Job Queue Metrics
        map('observability.task.enqueue', backends: [:metrics], priority: :high)
        map('observability.task.finalize', backends: [:trace])
        map('observability.step.backoff', backends: %i[trace metrics])
        map('observability.step.find_viable', backends: [:trace])
        map('observability.step.handle', backends: [:trace])
        map('observability.step.skip', backends: %i[trace metrics])
        map('observability.step.max_retries_reached', backends: %i[trace metrics], priority: :high)

        # Handler Execution Events
        map('step.before_handle', backends: [:trace], sampling_rate: 1.0)

        # Future events (for Phase 4.2.3 expansion)
        map('database.query_executed', backends: %i[trace metrics], sampling_rate: 0.1)
        map('dependency.resolved', backends: [:trace])
        map('batch.step_execution', backends: %i[trace metrics])
        map('memory.spike_detected', backends: [:metrics], priority: :critical)
        map('performance.slow_operation', backends: %i[trace metrics], priority: :high)
      end
    end
  end
end
