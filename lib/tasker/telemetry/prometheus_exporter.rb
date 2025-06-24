# frozen_string_literal: true

module Tasker
  module Telemetry
    # Prometheus exporter for converting native metrics to Prometheus format
    #
    # This exporter transforms metrics from the MetricsBackend singleton into
    # standard Prometheus text format for consumption by monitoring systems.
    #
    # @example Basic usage
    #   exporter = PrometheusExporter.new
    #   prometheus_text = exporter.export
    #
    # @example With custom backend
    #   exporter = PrometheusExporter.new(MetricsBackend.instance)
    #   prometheus_text = exporter.export
    class PrometheusExporter
      # Initialize exporter with optional metrics backend
      #
      # @param backend [MetricsBackend] The metrics backend to export from
      def initialize(backend = nil)
        @backend = backend || MetricsBackend.instance
      end

      # Export all metrics in Prometheus text format
      #
      # Returns metrics in the standard Prometheus exposition format as specified at:
      # https://prometheus.io/docs/instrumenting/exposition_formats/
      #
      # @return [String] Prometheus format text
      def export
        return '' unless telemetry_enabled?

        metrics_data = @backend.export
        return '' if metrics_data[:metrics].empty?

        output = []
        output << export_metadata(metrics_data)
        output << export_metrics(metrics_data[:metrics])
        "#{output.flatten.compact.join("\n")}\n"
      rescue StandardError => e
        # Log error but don't fail the export
        log_export_error(e)
        export_error_metric(e)
      end

      # Export metrics with error handling
      #
      # @return [Hash] Export result with success status and data
      def safe_export
        {
          success: true,
          data: export,
          timestamp: Time.current.iso8601,
          total_metrics: @backend.export[:total_metrics] || 0
        }
      rescue StandardError => e
        {
          success: false,
          error: e.message,
          timestamp: Time.current.iso8601,
          total_metrics: 0
        }
      end

      private

      # Export metadata and help text
      #
      # @param metadata [Hash] Metrics metadata
      # @return [Array<String>] Prometheus metadata lines
      def export_metadata(metadata)
        lines = []
        lines << '# Tasker metrics export'
        lines << "# GENERATED #{metadata[:timestamp]}"
        lines << "# TOTAL_METRICS #{metadata[:total_metrics]}"
        lines << ''
        lines
      end

      # Export all metrics by type
      #
      # @param metrics [Hash] Hash of metric name to metric data
      # @return [Array<String>] Prometheus metric lines
      def export_metrics(metrics)
        lines = []

        # Group metrics by type for better organization
        counters = metrics.select { |_, data| data[:type] == :counter }
        gauges = metrics.select { |_, data| data[:type] == :gauge }
        histograms = metrics.select { |_, data| data[:type] == :histogram }

        lines.concat(export_counters(counters)) if counters.any?
        lines.concat(export_gauges(gauges)) if gauges.any?
        lines.concat(export_histograms(histograms)) if histograms.any?

        lines
      end

      # Export counter metrics
      #
      # @param counters [Hash] Counter metrics data
      # @return [Array<String>] Prometheus counter lines
      def export_counters(counters)
        lines = []
        counters.each do |name, data|
          lines << ''
          lines << "# HELP #{name} #{help_text_for(name, :counter)}"
          lines << "# TYPE #{name} counter"
          lines << format_metric_line(name, data[:value], data[:labels])
        end
        lines
      end

      # Export gauge metrics
      #
      # @param gauges [Hash] Gauge metrics data
      # @return [Array<String>] Prometheus gauge lines
      def export_gauges(gauges)
        lines = []
        gauges.each do |name, data|
          lines << ''
          lines << "# HELP #{name} #{help_text_for(name, :gauge)}"
          lines << "# TYPE #{name} gauge"
          lines << format_metric_line(name, data[:value], data[:labels])
        end
        lines
      end

      # Export histogram metrics
      #
      # @param histograms [Hash] Histogram metrics data
      # @return [Array<String>] Prometheus histogram lines
      def export_histograms(histograms)
        lines = []
        histograms.each do |name, data|
          lines << ''
          lines << "# HELP #{name} #{help_text_for(name, :histogram)}"
          lines << "# TYPE #{name} histogram"

          # Export histogram buckets
          data[:buckets].each do |le, count|
            bucket_labels = data[:labels].merge(le: le.to_s)
            lines << format_metric_line("#{name}_bucket", count, bucket_labels)
          end

          # Export histogram sum and count
          lines << format_metric_line("#{name}_sum", data[:sum], data[:labels])
          lines << format_metric_line("#{name}_count", data[:count], data[:labels])
        end
        lines
      end

      # Format a single metric line
      #
      # @param name [String] Metric name
      # @param value [Numeric] Metric value
      # @param labels [Hash] Metric labels
      # @return [String] Formatted Prometheus metric line
      def format_metric_line(name, value, labels = {})
        if labels.empty?
          "#{name} #{value}"
        else
          label_string = format_labels(labels)
          "#{name}{#{label_string}} #{value}"
        end
      end

      # Format labels for Prometheus
      #
      # @param labels [Hash] Labels hash
      # @return [String] Formatted label string
      def format_labels(labels)
        labels.map do |key, value|
          # Escape backslashes first, then quotes in label values
          escaped_value = value.to_s.gsub('\\', '\\\\').gsub('"', '\\"')
          "#{key}=\"#{escaped_value}\""
        end.join(',')
      end

      # Generate help text for metrics
      #
      # @param name [String] Metric name
      # @param type [Symbol] Metric type
      # @return [String] Help text
      def help_text_for(name, type)
        case name
        when /task.*total/
          'Total number of tasks processed'
        when /task.*duration/
          'Task execution duration in seconds'
        when /step.*total/
          'Total number of steps executed'
        when /step.*duration/
          'Step execution duration in seconds'
        when /workflow.*total/
          'Total number of workflow orchestrations'
        when /event.*total/
          'Total number of events published'
        when /error.*total/
          'Total number of errors encountered'
        when /queue.*size/
          'Current queue size'
        when /active.*connections/
          'Number of active connections'
        else
          "Tasker #{type} metric: #{name}"
        end
      end

      # Check if telemetry is enabled
      #
      # @return [Boolean] True if telemetry is enabled
      def telemetry_enabled?
        return false unless defined?(Tasker.configuration)

        Tasker.configuration.telemetry.metrics_enabled
      end

      # Log export error with structured logging
      #
      # @param error [StandardError] The error that occurred
      def log_export_error(error)
        return unless defined?(Rails) && Rails.logger

        Rails.logger.error({
          message: 'Prometheus export failed',
          error: error.message,
          backtrace: error.backtrace&.first(5),
          timestamp: Time.current.iso8601,
          component: 'prometheus_exporter'
        }.to_json)
      end

      # Export error metric when export fails
      #
      # @param error [StandardError] The error that occurred
      # @return [String] Error metric in Prometheus format
      def export_error_metric(error)
        timestamp = Time.current.to_f
        <<~PROMETHEUS
          # Export error fallback metric
          # TYPE tasker_metrics_export_errors_total counter
          tasker_metrics_export_errors_total{error="#{error.class.name}"} 1 #{timestamp}
        PROMETHEUS
      end
    end
  end
end
