# frozen_string_literal: true

require_relative 'base_exporter'

module Tasker
  module Telemetry
    module Plugins
      # JSON format exporter for metrics data
      #
      # Exports metrics in structured JSON format with optional pretty printing
      # and custom field mapping.
      #
      # @example Basic Usage
      #   exporter = Tasker::Telemetry::Plugins::JsonExporter.new
      #   result = exporter.export(metrics_data, pretty: true)
      #
      # @example With Custom Field Mapping
      #   exporter = Tasker::Telemetry::Plugins::JsonExporter.new(
      #     field_mapping: {
      #       timestamp: 'collected_at',
      #       metrics: 'data'
      #     }
      #   )
      class JsonExporter < BaseExporter
        VERSION = '1.0.0'
        DESCRIPTION = 'JSON format exporter with customizable field mapping'

        # @param options [Hash] Configuration options
        # @option options [Hash] :field_mapping Custom field name mapping
        # @option options [Boolean] :include_metadata Include export metadata
        def initialize(options = {})
          super()
          @field_mapping = options.fetch(:field_mapping, {})
          @include_metadata = options.fetch(:include_metadata, true)
        end

        # Export metrics data as JSON
        #
        # @param metrics_data [Hash] Metrics data from MetricsBackend
        # @param options [Hash] Export options
        # @option options [Boolean] :pretty Pretty print JSON output
        # @option options [Hash] :additional_fields Extra fields to include
        # @return [Hash] Export result with JSON string
        def export(metrics_data, options = {})
          pretty = options.fetch(:pretty, false)
          additional_fields = options.fetch(:additional_fields, {})

          # Build export data with field mapping
          export_data = build_export_data(metrics_data, additional_fields)

          # Generate JSON
          json_output = if pretty
                          JSON.pretty_generate(export_data)
                        else
                          JSON.generate(export_data)
                        end

          {
            success: true,
            format: 'json',
            data: json_output,
            size_bytes: json_output.bytesize,
            metrics_count: metrics_data[:metrics]&.size || 0
          }
        end

        # Check if format is supported
        #
        # @param format [String, Symbol] Format to check
        # @return [Boolean] True if JSON format is supported
        def supports_format?(format)
          %w[json].include?(format.to_s.downcase)
        end

        # Get supported formats
        #
        # @return [Array<String>] List of supported formats
        def supported_formats
          %w[json]
        end

        private

        # Build export data structure with field mapping
        def build_export_data(metrics_data, additional_fields)
          export_data = {}

          # Apply field mapping or use defaults
          timestamp_field = @field_mapping.fetch(:timestamp, :timestamp)
          metrics_field = @field_mapping.fetch(:metrics, :metrics)
          total_metrics_field = @field_mapping.fetch(:total_metrics, :total_metrics)

          # Core data
          export_data[timestamp_field] = metrics_data[:timestamp]
          export_data[metrics_field] = format_metrics(metrics_data[:metrics] || {})
          export_data[total_metrics_field] = metrics_data[:total_metrics] || 0

          # Add metadata if enabled
          if @include_metadata
            metadata_field = @field_mapping.fetch(:metadata, :metadata)
            export_data[metadata_field] = {
              exporter: 'json',
              version: VERSION,
              exported_at: Time.current.iso8601,
              field_mapping: @field_mapping.any? ? @field_mapping : nil
            }.compact
          end

          # Add additional fields
          export_data.merge!(additional_fields) if additional_fields.any?

          export_data
        end

        # Format metrics for JSON export
        def format_metrics(metrics)
          # Handle malformed input gracefully
          return {} unless metrics.is_a?(Hash)
          return {} if metrics.empty?

          formatted = {}

          metrics.each do |metric_name, metric_data|
            # Ensure metric_data is a hash
            next unless metric_data.is_a?(Hash)

            formatted[metric_name] = {
              name: metric_data[:name],
              type: metric_data[:type],
              value: metric_data[:value],
              labels: metric_data[:labels] || {},
              help: metric_data[:help]
            }.compact
          end

          formatted
        end
      end
    end
  end
end
