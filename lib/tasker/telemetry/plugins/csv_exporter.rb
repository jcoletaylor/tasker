# frozen_string_literal: true

require 'csv'
require_relative 'base_exporter'

module Tasker
  module Telemetry
    module Plugins
      # CSV format exporter for metrics data
      #
      # Exports metrics in CSV format with configurable columns and headers.
      # Flattens metric labels into separate columns for tabular representation.
      #
      # @example Basic Usage
      #   exporter = Tasker::Telemetry::Plugins::CsvExporter.new
      #   result = exporter.export(metrics_data, include_headers: true)
      #
      # @example With Custom Columns
      #   exporter = Tasker::Telemetry::Plugins::CsvExporter.new(
      #     columns: %w[timestamp name type value status]
      #   )
      class CsvExporter < BaseExporter
        VERSION = '1.0.0'
        DESCRIPTION = 'CSV format exporter with configurable columns and label flattening'

        DEFAULT_COLUMNS = %w[
          timestamp
          name
          type
          value
          labels
        ].freeze

        # @param options [Hash] Configuration options
        # @option options [Array<String>] :columns Column names to include
        # @option options [String] :separator CSV field separator
        # @option options [Boolean] :flatten_labels Flatten labels into separate columns
        def initialize(options = {})
          super()
          @columns = options.fetch(:columns, DEFAULT_COLUMNS)
          @separator = options.fetch(:separator, ',')
          @flatten_labels = options.fetch(:flatten_labels, true)
        end

        # Export metrics data as CSV
        #
        # @param metrics_data [Hash] Metrics data from MetricsBackend
        # @param options [Hash] Export options
        # @option options [Boolean] :include_headers Include CSV headers
        # @option options [String] :row_separator Row separator character
        # @return [Hash] Export result with CSV string
        def export(metrics_data, options = {})
          include_headers = options.fetch(:include_headers, true)
          row_separator = options.fetch(:row_separator, "\n")

          metrics = metrics_data[:metrics] || {}
          timestamp = metrics_data[:timestamp]

          return empty_export if metrics.empty?

          # Build CSV data
          csv_data = build_csv_data(metrics, timestamp, include_headers, row_separator)

          {
            success: true,
            format: 'csv',
            data: csv_data,
            size_bytes: csv_data.bytesize,
            metrics_count: metrics.size,
            rows: metrics.size + (include_headers ? 1 : 0)
          }
        end

        # Check if format is supported
        #
        # @param format [String, Symbol] Format to check
        # @return [Boolean] True if CSV format is supported
        def supports_format?(format)
          %w[csv].include?(format.to_s.downcase)
        end

        # Get supported formats
        #
        # @return [Array<String>] List of supported formats
        def supported_formats
          %w[csv]
        end

        private

        # Build CSV data from metrics
        def build_csv_data(metrics, timestamp, include_headers, row_separator)
          # Determine all label keys if flattening
          all_label_keys = if @flatten_labels
                             extract_all_label_keys(metrics)
                           else
                             []
                           end

          # Build headers
          headers = build_headers(all_label_keys)

          # Build rows
          rows = []
          rows << headers if include_headers

          metrics.each_value do |metric_data|
            row = build_metric_row(metric_data, timestamp, all_label_keys)
            rows << row
          end

          # Generate CSV
          CSV.generate(col_sep: @separator, row_sep: row_separator) do |csv|
            rows.each { |row| csv << row }
          end
        end

        # Extract all unique label keys from metrics
        def extract_all_label_keys(metrics)
          label_keys = Set.new

          metrics.each_value do |metric_data|
            labels = metric_data[:labels] || {}
            label_keys.merge(labels.keys.map(&:to_s))
          end

          label_keys.to_a.sort
        end

        # Build CSV headers
        def build_headers(label_keys)
          headers = []

          @columns.each do |column|
            case column
            when 'labels'
              if @flatten_labels && label_keys.any?
                headers.concat(label_keys.map { |key| "label_#{key}" })
              else
                headers << 'labels'
              end
            else
              headers << column
            end
          end

          headers
        end

        # Build a single metric row
        def build_metric_row(metric_data, timestamp, label_keys)
          row = []
          labels = metric_data[:labels] || {}

          @columns.each do |column|
            case column
            when 'timestamp'
              row << timestamp
            when 'name'
              row << metric_data[:name]
            when 'type'
              row << metric_data[:type]
            when 'value'
              row << metric_data[:value]
            when 'labels'
              if @flatten_labels && label_keys.any?
                # Add each label as separate column
                label_keys.each do |key|
                  row << (labels[key.to_s] || labels[key.to_sym] || '')
                end
              else
                # Add labels as JSON string
                row << (labels.any? ? labels.to_json : '')
              end
            else
              # Custom column - try to get from metric data
              row << (metric_data[column.to_sym] || '')
            end
          end

          row
        end

        # Return empty export result
        def empty_export
          {
            success: true,
            format: 'csv',
            data: '',
            size_bytes: 0,
            metrics_count: 0,
            rows: 0
          }
        end
      end
    end
  end
end
