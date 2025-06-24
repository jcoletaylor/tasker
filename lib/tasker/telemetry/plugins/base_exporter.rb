# frozen_string_literal: true

module Tasker
  module Telemetry
    module Plugins
      # Base class for telemetry export plugins
      #
      # Provides a standard interface and common functionality for all export plugins.
      # Plugins should inherit from this class and implement the required methods.
      #
      # @example Creating a custom exporter
      #   class MyCustomExporter < Tasker::Telemetry::Plugins::BaseExporter
      #     def export(metrics_data, options = {})
      #       # Implementation here
      #       log_plugin_event(:info, "Custom export completed", metrics_count: metrics_data.size)
      #     end
      #
      #     def supports_format?(format)
      #       format.to_s == 'custom'
      #     end
      #
      #     def supported_formats
      #       ['custom']
      #     end
      #   end
      class BaseExporter
        include Tasker::Concerns::StructuredLogging

        # Plugin metadata
        attr_reader :name, :version, :description

        def initialize(name: nil, version: '1.0.0', description: nil)
          # Safe class name extraction for test environments where class.name might be nil
          default_name = if self.class.name
                           self.class.name.demodulize.underscore
                         else
                           'anonymous_exporter'
                         end

          @name = name || default_name
          @version = version
          @description = description || "#{@name} telemetry exporter"
        end

        # Export metrics data (must be implemented by subclasses)
        #
        # @param metrics_data [Hash] Metrics data to export
        # @param options [Hash] Export options
        # @return [Hash] Export result with :success, :format, :data keys
        # @raise [NotImplementedError] If not implemented by subclass
        def export(metrics_data, options = {})
          raise NotImplementedError, "#{self.class.name} must implement #export method"
        end

        # Check if plugin supports a specific format (must be implemented by subclasses)
        #
        # @param format [String, Symbol] Format to check
        # @return [Boolean] Whether format is supported
        # @raise [NotImplementedError] If not implemented by subclass
        def supports_format?(format)
          raise NotImplementedError, "#{self.class.name} must implement #supports_format? method"
        end

        # Get supported formats (should be implemented by subclasses)
        #
        # @return [Array<String>] Supported export formats
        def supported_formats
          []
        end

        # Plugin lifecycle callbacks (optional overrides)

        # Called when cache sync occurs
        #
        # @param sync_data [Hash] Cache sync information
        def on_cache_sync(sync_data)
          # Default: no action
        end

        # Called when export is requested
        #
        # @param request_data [Hash] Export request information
        def on_export_request(request_data)
          # Default: no action
        end

        # Called when export completes
        #
        # @param completion_data [Hash] Export completion information
        def on_export_complete(completion_data)
          # Default: no action
        end

        # Safe export wrapper with error handling and timing
        #
        # @param metrics_data [Hash] Metrics data to export
        # @param options [Hash] Export options
        # @return [Hash] Export result with success/error information
        def safe_export(metrics_data, options = {})
          start_time = Time.current

          begin
            # Validate metrics data structure
            validate_metrics_data!(metrics_data) if respond_to?(:validate_metrics_data!, true)

            result = export(metrics_data, options)

            duration = ((Time.current - start_time) * 1000).round(2)

            log_plugin_event(:info, 'Plugin export completed',
                             metrics_count: metrics_data.size,
                             duration_ms: duration,
                             success: true)

            {
              success: true,
              format: result[:format] || 'unknown',
              data: result[:data],
              result: result, # Include the full result for test compatibility
              plugin: { name: @name, version: @version }, # Add plugin field for test compatibility
              metrics_count: metrics_data.size,
              duration_ms: duration,
              plugin_name: @name,
              plugin_version: @version
            }
          rescue StandardError => e
            duration = ((Time.current - start_time) * 1000).round(2)

            log_plugin_event(:error, 'Plugin export failed',
                             metrics_count: metrics_data.size,
                             duration_ms: duration,
                             error: e.message,
                             success: false)

            {
              success: false,
              error: e.message,
              metrics_count: metrics_data.size,
              duration_ms: duration,
              plugin_name: @name,
              plugin_version: @version
            }
          end
        end

        # Get plugin metadata
        #
        # @return [Hash] Plugin metadata
        def metadata
          # Use class constants when available, otherwise use instance variables
          version = if self.class.const_defined?(:VERSION)
                      self.class.const_get(:VERSION)
                    else
                      @version == '1.0.0' ? 'unknown' : @version
                    end

          description = if self.class.const_defined?(:DESCRIPTION)
                          self.class.const_get(:DESCRIPTION)
                        else
                          nil # Return nil when no DESCRIPTION constant is defined
                        end

          {
            name: @name,
            version: version,
            description: description,
            supported_formats: supported_formats,
            class_name: self.class.name
          }
        end

        # Alias for metadata (for test compatibility)
        alias plugin_info metadata

        private

        # Validate metrics data structure
        #
        # @param metrics_data [Hash] Metrics data to validate
        # @raise [ArgumentError] If data structure is invalid
        def validate_metrics_data!(metrics_data)
          raise ArgumentError, "Metrics data must be a Hash, got #{metrics_data.class}" unless metrics_data.is_a?(Hash)

          raise ArgumentError, 'Metrics data must contain :metrics key' unless metrics_data.key?(:metrics)

          return if metrics_data.key?(:timestamp)

          raise ArgumentError, 'Metrics data must contain :timestamp key'
        end

        protected

        # Structured logging helper for plugin events
        #
        # @param level [Symbol] Log level
        # @param message [String] Log message
        # @param context [Hash] Additional context
        def log_plugin_event(level, message, **context)
          # Safe class name extraction to avoid demodulize errors
          class_name = self.class.name || 'AnonymousExporter'

          log_structured(level, message,
                         entity_type: 'telemetry_plugin',
                         entity_id: @name,
                         plugin_name: @name,
                         plugin_version: @version,
                         plugin_class: class_name,
                         **context)
        rescue StandardError => e
          # Fallback logging if structured logging fails
          Rails.logger.debug { "Structured logging failed: #{e.message}" }
          Rails.logger.debug { "#{level.upcase}: #{message}" }
        end

        # Structured logging helper for plugin performance events
        #
        # @param operation [String] Operation name
        # @param duration [Float] Duration in seconds
        # @param context [Hash] Additional context
        def log_plugin_performance(operation, duration, **context)
          log_performance_event("plugin_#{operation}", duration,
                                entity_type: 'telemetry_plugin',
                                entity_id: @name,
                                plugin_name: @name,
                                plugin_version: @version,
                                **context)
        end

        # Structured logging helper for plugin errors
        #
        # @param exception [Exception] Exception to log
        # @param context [Hash] Additional context
        def log_plugin_exception(exception, **context)
          log_exception(exception,
                        context: {
                          entity_type: 'telemetry_plugin',
                          entity_id: @name,
                          plugin_name: @name,
                          plugin_version: @version,
                          **context
                        })
        end
      end
    end
  end
end
