# frozen_string_literal: true

module Tasker
  module Telemetry
    # Service for exporting metrics in various formats with delivery coordination
    #
    # **Phase 4.2.2.3.3**: Service handles the business logic of metrics export,
    # including format conversion, delivery, and storage. This is called by
    # MetricsExportJob but can also be used independently.
    #
    # Key Features:
    # - Multiple export formats (Prometheus, JSON, CSV)
    # - Prometheus remote write integration
    # - Configurable storage backends
    # - Comprehensive error handling and logging
    #
    # @example Basic usage
    #   service = MetricsExportService.new
    #   result = service.export_metrics(format: :prometheus, metrics_data: data)
    #
    # @example With custom configuration
    #   service = MetricsExportService.new(
    #     prometheus_config: { endpoint: 'http://localhost:9090/api/v1/write' }
    #   )
    #
    class MetricsExportService
      include Tasker::Concerns::StructuredLogging

      attr_reader :config

      # Initialize metrics export service
      #
      # @param config [Hash] Service configuration overrides
      def initialize(config = {})
        @config = default_config.merge(config)
      end

      # Export metrics in specified format
      #
      # Main entry point for exporting metrics. Handles format routing,
      # data conversion, delivery, and comprehensive error handling.
      #
      # @param format [Symbol] Export format (:prometheus, :json, :csv)
      # @param metrics_data [Hash] Raw metrics data to export
      # @param context [Hash] Additional context (job_id, coordinator_instance, etc.)
      # @return [Hash] Export result with success status and details
      def export_metrics(format:, metrics_data:, context: {})
        @export_context = context
        start_time = Time.current

        log_export_started(format, metrics_data, context)

        case format.to_sym
        when :prometheus
          result = export_prometheus_metrics(metrics_data)
        when :json
          result = export_json_metrics(metrics_data)
        when :csv
          result = export_csv_metrics(metrics_data)
        else
          return unsupported_format_result(format)
        end

        duration = Time.current - start_time
        log_export_completed(format, result, duration)

        result.merge(
          format: format,
          duration: duration,
          exported_at: Time.current.iso8601,
          context: context
        )
      rescue StandardError => e
        log_export_error(format, e, context)
        {
          success: false,
          format: format,
          error: e.message,
          error_type: e.class.name,
          context: context
        }
      end

      private

      # Export metrics in Prometheus format
      #
      # @param metrics_data [Hash] Raw metrics data
      # @return [Hash] Export result
      def export_prometheus_metrics(metrics_data)
        unless prometheus_configured?
          return {
            success: false,
            error: 'Prometheus endpoint not configured',
            skipped: true
          }
        end

        # Format metrics for Prometheus
        prometheus_data = format_prometheus_metrics(metrics_data)
        log_prometheus_formatting_success(prometheus_data)

        # Send to Prometheus endpoint
        delivery_result = send_to_prometheus(prometheus_data)

        {
          success: true,
          delivery: delivery_result,
          data_length: prometheus_data.length,
          lines_count: prometheus_data.lines.count,
          endpoint: prometheus_config[:endpoint]
        }
      end

      # Export metrics in JSON format
      #
      # @param metrics_data [Hash] Raw metrics data
      # @return [Hash] Export result
      def export_json_metrics(metrics_data)
        json_data = metrics_data.to_json
        storage_result = store_json_export(json_data)

        {
          success: true,
          storage: storage_result,
          data_length: json_data.length,
          format_type: 'application/json'
        }
      end

      # Export metrics in CSV format
      #
      # @param metrics_data [Hash] Raw metrics data
      # @return [Hash] Export result
      def export_csv_metrics(metrics_data)
        csv_data = format_csv_metrics(metrics_data)
        storage_result = store_csv_export(csv_data)

        {
          success: true,
          storage: storage_result,
          lines_count: csv_data.lines.count,
          format_type: 'text/csv'
        }
      end

      # Format metrics for Prometheus remote write
      #
      # @param metrics_data [Hash] Raw metrics data
      # @return [String] Prometheus formatted metrics
      def format_prometheus_metrics(metrics_data)
        prometheus_lines = []
        timestamp_ms = Time.current.to_i * 1000
        metric_prefix = prometheus_config[:metric_prefix] || 'tasker'

        metrics_data[:metrics]&.each do |metric_name, metric_data|
          case metric_data[:type]
          when :counter
            prometheus_lines << "#{metric_prefix}_#{metric_name}_total #{metric_data[:value]} #{timestamp_ms}"
          when :gauge
            prometheus_lines << "#{metric_prefix}_#{metric_name} #{metric_data[:value]} #{timestamp_ms}"
          when :histogram
            # Prometheus histogram format
            metric_data[:buckets]&.each do |bucket, count|
              prometheus_lines << "#{metric_prefix}_#{metric_name}_bucket{le=\"#{bucket}\"} #{count} #{timestamp_ms}"
            end
            prometheus_lines << "#{metric_prefix}_#{metric_name}_sum #{metric_data[:sum]} #{timestamp_ms}"
            prometheus_lines << "#{metric_prefix}_#{metric_name}_count #{metric_data[:count]} #{timestamp_ms}"
          end
        end

        prometheus_lines.join("\n")
      end

      # Format metrics for CSV export
      #
      # @param metrics_data [Hash] Raw metrics data
      # @return [String] CSV formatted metrics
      def format_csv_metrics(metrics_data)
        csv_lines = ['metric_name,type,value,timestamp,instance']
        timestamp = Time.current.iso8601
        instance_id = @export_context[:coordinator_instance] || 'unknown'

        metrics_data[:metrics]&.each do |metric_name, metric_data|
          csv_lines << "#{metric_name},#{metric_data[:type]},#{metric_data[:value]},#{timestamp},#{instance_id}"
        end

        csv_lines.join("\n")
      end

      # Send metrics to Prometheus remote write endpoint
      #
      # @param prometheus_data [String] Prometheus formatted metrics
      # @return [Hash] Delivery result
      def send_to_prometheus(prometheus_data)
        endpoint = prometheus_config[:endpoint]

        headers = {
          'Content-Type' => 'application/x-protobuf',
          'Content-Encoding' => prometheus_config[:compression] || 'snappy',
          'X-Prometheus-Remote-Write-Version' => '0.1.0'
        }

        # Add authentication if configured
        if prometheus_config[:username] && prometheus_config[:password]
          auth = Base64.strict_encode64("#{prometheus_config[:username]}:#{prometheus_config[:password]}")
          headers['Authorization'] = "Basic #{auth}"
        end

        response = Net::HTTP.post(endpoint, prometheus_data, headers)

        raise "Prometheus remote write failed: #{response.code} #{response.body}" if response.code.to_i >= 400

        log_prometheus_delivery_success(response.code, endpoint)

        {
          success: true,
          response_code: response.code,
          endpoint: endpoint.to_s,
          data_length: prometheus_data.length
        }
      rescue StandardError => e
        log_prometheus_delivery_error(e, endpoint)
        raise
      end

      # Store JSON export
      #
      # @param json_data [String] JSON formatted metrics
      # @return [Hash] Storage result
      def store_json_export(json_data)
        storage_path = generate_storage_path('json')

        ensure_storage_directory(storage_path)
        File.write(storage_path, json_data)

        log_storage_success('JSON', storage_path, json_data.length)

        {
          success: true,
          storage_path: storage_path.to_s,
          data_length: json_data.length,
          storage_type: 'filesystem'
        }
      end

      # Store CSV export
      #
      # @param csv_data [String] CSV formatted metrics
      # @return [Hash] Storage result
      def store_csv_export(csv_data)
        storage_path = generate_storage_path('csv')

        ensure_storage_directory(storage_path)
        File.write(storage_path, csv_data)

        log_storage_success('CSV', storage_path, csv_data.length)

        {
          success: true,
          storage_path: storage_path.to_s,
          lines_count: csv_data.lines.count,
          storage_type: 'filesystem'
        }
      end

      # Generate storage path for export files
      #
      # @param extension [String] File extension
      # @return [Pathname] Storage path
      def generate_storage_path(extension)
        timestamp = Time.current.strftime('%Y%m%d_%H%M%S')
        instance_id = @export_context[:coordinator_instance] || 'unknown'
        filename = "metrics_export_#{instance_id}_#{timestamp}.#{extension}"

        storage_root = @config[:storage_root] || Rails.root.join('tmp/metrics_exports')
        Pathname.new(storage_root).join(filename)
      end

      # Ensure storage directory exists
      #
      # @param storage_path [Pathname] Full path to storage file
      def ensure_storage_directory(storage_path)
        FileUtils.mkdir_p(storage_path.dirname)
      end

      # Check if Prometheus is configured
      #
      # @return [Boolean] True if Prometheus endpoint is configured
      def prometheus_configured?
        prometheus_config[:endpoint].present?
      end

      # Get Prometheus configuration
      #
      # @return [Hash] Prometheus configuration
      def prometheus_config
        @prometheus_config ||= @config[:prometheus_config] || default_prometheus_config
      end

      # Generate result for unsupported format
      #
      # @param format [Symbol] Unsupported format
      # @return [Hash] Error result
      def unsupported_format_result(format)
        log_unsupported_format(format)
        {
          success: false,
          error: "Unsupported export format: #{format}",
          supported_formats: %i[prometheus json csv]
        }
      end

      # Get default service configuration
      #
      # @return [Hash] Default configuration
      def default_config
        {
          storage_root: Rails.root.join('tmp/metrics_exports'),
          prometheus_config: default_prometheus_config
        }
      end

      # Get default Prometheus configuration from Tasker
      #
      # @return [Hash] Default Prometheus configuration
      def default_prometheus_config
        Tasker.configuration.telemetry.prometheus
      rescue StandardError
        {}
      end

      # Logging methods for export service events

      def log_export_started(format, metrics_data, context)
        log_structured(:info, 'Metrics export started',
                       format: format,
                       metrics_count: metrics_data[:metrics]&.size || 0,
                       job_id: context[:job_id],
                       coordinator_instance: context[:coordinator_instance])
      end

      def log_export_completed(format, result, duration)
        log_structured(:info, 'Metrics export completed',
                       format: format,
                       success: result[:success],
                       duration: duration,
                       result_summary: result.except(:context))
      end

      def log_export_error(format, error, context)
        log_structured(:error, 'Metrics export error',
                       format: format,
                       error: error.message,
                       error_class: error.class.name,
                       backtrace: error.backtrace&.first(5),
                       job_id: context[:job_id])
      end

      def log_prometheus_formatting_success(prometheus_data)
        log_structured(:debug, 'Prometheus metrics formatted',
                       data_length: prometheus_data.length,
                       lines_count: prometheus_data.lines.count)
      end

      def log_prometheus_delivery_success(response_code, endpoint)
        log_structured(:info, 'Prometheus delivery successful',
                       response_code: response_code,
                       endpoint: endpoint.to_s)
      end

      def log_prometheus_delivery_error(error, endpoint)
        log_structured(:error, 'Prometheus delivery failed',
                       error: error.message,
                       endpoint: endpoint.to_s)
      end

      def log_storage_success(format_type, storage_path, size)
        log_structured(:info, 'Export storage successful',
                       format_type: format_type,
                       storage_path: storage_path.to_s,
                       size: size)
      end

      def log_unsupported_format(format)
        log_structured(:error, 'Unsupported export format',
                       format: format,
                       supported_formats: %i[prometheus json csv])
      end
    end
  end
end
