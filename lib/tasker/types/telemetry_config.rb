# frozen_string_literal: true

module Tasker
  module Types
    # Configuration type for telemetry and observability settings
    #
    # This configuration handles telemetry, logging, and observability settings for Tasker.
    # It provides the same functionality as the original TelemetryConfiguration but with
    # dry-struct type safety and immutability.
    #
    # @example Basic usage
    #   config = TelemetryConfig.new(
    #     enabled: false,
    #     service_name: 'my-service'
    #   )
    #
    # @example Full configuration
    #   config = TelemetryConfig.new(
    #     enabled: true,
    #     service_name: 'my-tasker-app',
    #     service_version: '2.0.0',
    #     filter_parameters: [:password, :secret],
    #     filter_mask: '[REDACTED]'
    #   )
    class TelemetryConfig < BaseConfig
      transform_keys(&:to_sym)

      # Whether telemetry is enabled
      #
      # @!attribute [r] enabled
      #   @return [Boolean] Whether telemetry is enabled
      attribute :enabled, Types::Bool.default(true)

      # Service name for OpenTelemetry
      #
      # @!attribute [r] service_name
      #   @return [String] Service name for telemetry
      attribute :service_name, Types::String.default('tasker')

      # Service version for OpenTelemetry
      #
      # @!attribute [r] service_version
      #   @return [String] Service version for telemetry
      attribute :service_version, Types::String.default(proc { Tasker::VERSION }.freeze, shared: true)

      # Parameters to filter from logs and telemetry
      # Can contain symbols, strings, or regex patterns as supported by Rails
      #
      # @!attribute [r] filter_parameters
      #   @return [Array<Symbol, String, Regexp>] Parameters to filter
      attribute :filter_parameters, Types::Array.of(Types.Interface(:to_s)).default(proc {
        default_filter_parameters
      }.freeze, shared: true)

      # The mask to use when filtering sensitive parameters
      #
      # @!attribute [r] filter_mask
      #   @return [String] Filter mask string
      attribute :filter_mask, Types::String.default('[FILTERED]')

      # Structured logging configuration
      #
      # @!attribute [r] structured_logging_enabled
      #   @return [Boolean] Whether structured logging is enabled
      attribute :structured_logging_enabled, Types::Bool.default(true)

      # Correlation ID header name for HTTP propagation
      #
      # @!attribute [r] correlation_id_header
      #   @return [String] Header name for correlation ID
      attribute :correlation_id_header, Types::String.default('X-Correlation-ID')

      # Log level for structured logging
      #
      # @!attribute [r] log_level
      #   @return [String] Log level (debug, info, warn, error, fatal)
      attribute :log_level, Types::String.default('info')

      # Log output format
      #
      # @!attribute [r] log_format
      #   @return [String] Log format (json, pretty_json, logfmt)
      attribute :log_format, Types::String.default('json')

      # Metrics configuration
      #
      # @!attribute [r] metrics_enabled
      #   @return [Boolean] Whether metrics collection is enabled
      attribute :metrics_enabled, Types::Bool.default(true)

      # Metrics endpoint path
      #
      # @!attribute [r] metrics_endpoint
      #   @return [String] Path for metrics endpoint
      attribute :metrics_endpoint, Types::String.default('/tasker/metrics')

      # Metrics output format
      #
      # @!attribute [r] metrics_format
      #   @return [String] Metrics format (prometheus, json)
      attribute :metrics_format, Types::String.default('prometheus')

      # Whether metrics endpoint requires authentication
      #
      # @!attribute [r] metrics_auth_required
      #   @return [Boolean] Whether metrics endpoint requires auth
      attribute :metrics_auth_required, Types::Bool.default(false)

      # Performance monitoring configuration
      #
      # @!attribute [r] performance_monitoring_enabled
      #   @return [Boolean] Whether performance monitoring is enabled
      attribute :performance_monitoring_enabled, Types::Bool.default(true)

      # Threshold for slow query detection (seconds)
      #
      # @!attribute [r] slow_query_threshold_seconds
      #   @return [Float] Slow query threshold in seconds
      attribute :slow_query_threshold_seconds, Types::Float.default(1.0)

      # Memory usage threshold for spike detection (MB)
      #
      # @!attribute [r] memory_threshold_mb
      #   @return [Integer] Memory threshold in megabytes
      attribute :memory_threshold_mb, Types::Integer.default(100)

      # Event sampling rate (0.0 to 1.0)
      #
      # @!attribute [r] event_sampling_rate
      #   @return [Float] Sampling rate for events
      attribute :event_sampling_rate, Types::Float.default(1.0)

      # Events to filter out from collection
      #
      # @!attribute [r] filtered_events
      #   @return [Array<String>] List of event names to skip
      attribute :filtered_events, Types::Array.of(Types::String).default([].freeze)

      # Maximum number of metric samples to store in memory
      #
      # @!attribute [r] max_stored_samples
      #   @return [Integer] Maximum stored samples
      attribute :max_stored_samples, Types::Integer.default(1000)

      # How long to retain metrics data (hours)
      #
      # @!attribute [r] metrics_retention_hours
      #   @return [Integer] Retention period in hours
      attribute :metrics_retention_hours, Types::Integer.default(24)

      # Advanced telemetry configuration options
      #
      # @!attribute [r] config
      #   @return [Hash] Advanced configuration options
      attribute :config, Types::Hash.default(proc { default_telemetry_config }.freeze, shared: true)

      # Get the default filter parameters from Rails or use a default set
      #
      # @return [Array<Symbol>] Default parameters to filter
      def self.default_filter_parameters
        if defined?(Rails) && Rails.application&.config&.filter_parameters&.any?
          Rails.application.config.filter_parameters.dup
        else
          %i[passw email secret token _key crypt salt certificate otp ssn]
        end
      end

      # Get default telemetry configuration
      #
      # @return [Hash] Default telemetry configuration options
      def self.default_telemetry_config
        {
          # Batch processing options
          batch_events: false, # Set to true to enable event batching
          buffer_size: 100, # Maximum events to buffer before flushing
          flush_interval: 5, # Maximum time between flushes (in seconds)

          # Event filtering options
          filtered_events: [], # List of event names to skip recording

          # Performance options
          enable_memoization: true, # Cache frequently accessed attributes

          # Production optimizations
          async_processing: false, # Process events asynchronously (future enhancement)
          sampling_rate: 1.0 # Sample rate for events (1.0 = 100%, 0.1 = 10%)
        }.freeze
      end

      # Update telemetry configuration with custom options
      #
      # This method creates a new instance with merged configuration.
      # Since dry-struct types are immutable, this returns a new instance.
      #
      # @param options [Hash] Custom telemetry configuration options
      # @return [TelemetryConfig] New instance with updated configuration
      def configure_telemetry(options = {})
        new_config = config.merge(options)
        self.class.new(to_h.merge(config: new_config))
      end

      # Check if telemetry batching is enabled
      #
      # @return [Boolean] True if batching is enabled
      def batching_enabled?
        config[:batch_events] || false
      end

      # Get or create a parameter filter for sensitive data
      #
      # @return [ActiveSupport::ParameterFilter, nil] The parameter filter
      def parameter_filter
        return nil unless filter_parameters.any?

        return unless defined?(ActiveSupport::ParameterFilter)

        ActiveSupport::ParameterFilter.new(filter_parameters, mask: filter_mask)
      end

      private

      # Use class method for default filter parameters
      def default_filter_parameters
        self.class.default_filter_parameters
      end

      # Use class method for default telemetry config
      def default_telemetry_config
        self.class.default_telemetry_config
      end
    end
  end
end
