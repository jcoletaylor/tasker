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
      attribute :filter_parameters, Types::Array.of(Types.Interface(:to_s)).default(proc { default_filter_parameters }.freeze, shared: true)

      # The mask to use when filtering sensitive parameters
      #
      # @!attribute [r] filter_mask
      #   @return [String] Filter mask string
      attribute :filter_mask, Types::String.default('[FILTERED]')

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
