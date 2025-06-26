# frozen_string_literal: true

require 'concurrent-ruby'
require 'securerandom'
require_relative 'plugin_registry'

module Tasker
  module Telemetry
    # ExportCoordinator manages export coordination and integrates with PluginRegistry
    #
    # This class now uses the unified PluginRegistry for plugin management,
    # eliminating duplication and providing consistent plugin handling across
    # the telemetry system.
    class ExportCoordinator
      include Singleton
      include Tasker::Concerns::StructuredLogging

      def initialize
        @plugin_registry = PluginRegistry.instance
        @event_bus = Tasker::Events::Publisher.instance
        @mutex = Mutex.new

        log_structured(:info, 'ExportCoordinator initialized',
                       entity_type: 'export_coordinator',
                       event_type: :initialized)
      end

      # Register a plugin for export coordination (delegates to PluginRegistry)
      #
      # @param name [String, Symbol] Plugin identifier
      # @param plugin [Object] Plugin instance implementing required interface
      # @param replace [Boolean] Whether to replace existing plugin
      # @param options [Hash] Plugin configuration options
      # @return [Boolean] True if registration successful
      def register_plugin(name, plugin, replace: false, **options)
        # Register with the unified PluginRegistry
        result = @plugin_registry.register(name, plugin, replace: replace, **options)

        if result
          # Publish coordination event
          publish_event(Events::ExportEvents::PLUGIN_REGISTERED, {
                          plugin_name: name.to_s,
                          plugin_class: plugin.class.name,
                          options: options.merge(replace: replace),
                          timestamp: Time.current.iso8601
                        })

          log_structured(:info, 'Export plugin registered via coordinator',
                         entity_type: 'export_plugin',
                         entity_id: name.to_s,
                         plugin_name: name.to_s,
                         plugin_class: plugin.class.name,
                         options: options.merge(replace: replace),
                         event_type: :registered)
        end

        result
      end

      # Unregister a plugin (delegates to PluginRegistry)
      #
      # @param name [String, Symbol] Plugin identifier
      # @return [Boolean] True if unregistered successfully
      def unregister_plugin(name)
        # Get plugin info before unregistering
        plugin_info = @plugin_registry.get_plugin(name.to_s)

        result = @plugin_registry.unregister(name)

        if result && plugin_info
            publish_event(Events::ExportEvents::PLUGIN_UNREGISTERED, {
                            plugin_name: name.to_s,
                          plugin_class: plugin_info.class.name,
                            timestamp: Time.current.iso8601
                          })

          log_structured(:info, 'Export plugin unregistered via coordinator',
                         entity_type: 'export_plugin',
                         entity_id: name.to_s,
                         plugin_name: name.to_s,
                         plugin_class: plugin_info.class.name,
                         event_type: :unregistered)
        end

        result
      end

      # Get registered plugins (delegates to PluginRegistry)
      #
      # @return [Hash] Registered plugins
      def registered_plugins
        @plugin_registry.all_plugins
      end

      # Get plugins that support a specific format
      #
      # @param format [String, Symbol] Format to search for
      # @return [Array<Object>] Array of plugin instances
      def plugins_for_format(format)
        @plugin_registry.find_by_format(format)
      end

      # Check if a format is supported by any registered plugin
      #
      # @param format [String, Symbol] Format to check
      # @return [Boolean] True if format is supported
      def supports_format?(format)
        @plugin_registry.supports_format?(format)
      end

      # Get all supported formats across registered plugins
      #
      # @return [Array<String>] Array of supported format names
      def supported_formats
        @plugin_registry.supported_formats
      end

      # Coordinate cache sync event
      #
      # @param sync_result [Hash] Result from cache sync operation
      def coordinate_cache_sync(sync_result)
        publish_event(Events::ExportEvents::CACHE_SYNCED, {
                        strategy: sync_result[:strategy],
                        metrics_count: sync_result[:metrics_count],
                        duration_ms: sync_result[:duration_ms],
                        success: sync_result[:success],
                        timestamp: Time.current.iso8601
                      })

        # Notify plugins of cache sync
        notify_plugins(:on_cache_sync, sync_result)
      end

      # Coordinate export request
      #
      # @param export_format [String] Requested export format
      # @param options [Hash] Export options
      # @return [String] Export ID
      def coordinate_export_request(export_format, options = {})
        export_id = SecureRandom.uuid

        publish_event(Events::ExportEvents::EXPORT_REQUESTED, {
                        export_id: export_id,
                        format: export_format,
                        options: options,
                        timestamp: Time.current.iso8601
                      })

        # Notify plugins of export request
        notify_plugins(:on_export_request, {
                         export_id: export_id,
                         format: export_format,
                         options: options
                       })

        export_id
      end

      # Coordinate export completion
      #
      # @param export_id [String] Export identifier
      # @param result [Hash] Export result
      def coordinate_export_completion(export_id, result)
        if result[:success]
          publish_event(Events::ExportEvents::EXPORT_COMPLETED, {
                          export_id: export_id,
                          format: result[:format],
                          metrics_count: result[:metrics_count],
                          duration_ms: result[:duration_ms],
                          timestamp: Time.current.iso8601
                        })
        else
          publish_event(Events::ExportEvents::EXPORT_FAILED, {
                          export_id: export_id,
                          format: result[:format],
                          error: result[:error],
                          timestamp: Time.current.iso8601
                        })
        end

        # Notify plugins of export completion
        notify_plugins(:on_export_complete, {
                         export_id: export_id,
                         result: result
                       })
      end

      # Execute coordinated export with distributed locking and plugin coordination
      #
      # @param format [Symbol] Export format (e.g., :prometheus, :json, :csv)
      # @param include_instances [Boolean] Whether to include instance-specific data
      # @param options [Hash] Additional export options
      # @return [Hash] Export result with success status and data or error
      def execute_coordinated_export(format:, include_instances: false, **options)
        correlation_id = SecureRandom.uuid
        start_time = Time.current

        log_structured(
          :info,
          'Starting coordinated export',
          entity_type: 'export_coordination',
          entity_id: correlation_id,
          format: format,
          include_instances: include_instances,
          options: options
        )

        begin
          # Check if format is supported
          unless supports_format?(format)
            return {
              success: false,
              error: "Unsupported export format: #{format}",
              supported_formats: supported_formats
            }
          end

          # Publish export requested event
          @event_bus.publish(
            Tasker::Telemetry::Events::ExportEvents::EXPORT_REQUESTED,
            {
              correlation_id: correlation_id,
              format: format,
              include_instances: include_instances,
              options: options,
              timestamp: start_time
            }
          )

          # Get metrics data from backend
          metrics_backend = Tasker::Telemetry::MetricsBackend.instance
          metrics_data = if include_instances
                           metrics_backend.export_distributed_metrics
                         else
                           metrics_backend.export_metrics
                         end

          # Execute plugin-based export using PluginRegistry
          export_result = coordinate_plugin_export(format, metrics_data, correlation_id)

          duration_ms = ((Time.current - start_time) * 1000).round(2)

          if export_result[:success]
          result = {
            success: true,
              format: format,
              data: export_result[:data],
              metrics_count: metrics_data.size,
              duration_ms: duration_ms,
              correlation_id: correlation_id
            }

            @event_bus.publish(
              Tasker::Telemetry::Events::ExportEvents::EXPORT_COMPLETED,
              result.merge(timestamp: Time.current)
          )

          log_structured(
            :info,
            'Coordinated export completed successfully',
            entity_type: 'export_coordination',
            entity_id: correlation_id,
            format: format,
              metrics_count: result[:metrics_count],
              duration_ms: duration_ms
            )
          else
            result = {
              success: false,
              format: format,
              error: export_result[:error],
              duration_ms: duration_ms,
              correlation_id: correlation_id
            }

            @event_bus.publish(
              Tasker::Telemetry::Events::ExportEvents::EXPORT_FAILED,
              result.merge(timestamp: Time.current)
            )

            log_structured(
              :error,
              'Coordinated export failed',
              entity_type: 'export_coordination',
              entity_id: correlation_id,
              format: format,
              error: export_result[:error],
              duration_ms: duration_ms
            )
          end

          result
        rescue StandardError => e
          duration_ms = ((Time.current - start_time) * 1000).round(2)

          result = {
            success: false,
            format: format,
            error: e.message,
            duration_ms: duration_ms,
            correlation_id: correlation_id
          }

          @event_bus.publish(
            Tasker::Telemetry::Events::ExportEvents::EXPORT_FAILED,
            result.merge(timestamp: Time.current)
          )

          log_structured(
            :error,
            'Coordinated export exception',
            entity_type: 'export_coordination',
            entity_id: correlation_id,
            format: format,
            error: e.message,
            error_class: e.class.name,
            duration_ms: duration_ms
          )

          result
        end
      end

      # Get comprehensive export coordination statistics
      #
      # @return [Hash] Detailed statistics about export coordination
      def stats
        plugin_stats = @plugin_registry.stats

        {
          export_coordinator: {
            initialized_at: @initialized_at || Time.current,
            total_plugins: plugin_stats[:total_plugins],
            supported_formats: plugin_stats[:supported_formats],
            plugins_by_format: plugin_stats[:plugins_by_format],
            average_formats_per_plugin: plugin_stats[:average_formats_per_plugin]
          },
          plugin_registry_stats: plugin_stats
        }
      end

      # Legacy method for backward compatibility (now delegates to PluginRegistry)
      #
      # @return [Boolean] True if cleared successfully
      def clear_plugins!
        @plugin_registry.clear!
      end

      # Extend cache TTL for distributed scenarios
      #
      # @param extension_duration [Integer] Extension duration in seconds
      def extend_cache_ttl(extension_duration)
        correlation_id = SecureRandom.uuid

        log_structured(
          :info,
          'Extending cache TTL for distributed export',
          entity_type: 'cache_coordination',
          entity_id: correlation_id,
          extension_duration: extension_duration
        )

        begin
          # Get cache backend and extend TTL
          cache_backend = Tasker::Telemetry::CacheBackend.instance
          result = cache_backend.extend_ttl(extension_duration)

          if result[:success]
            @event_bus.publish(
              Tasker::Telemetry::Events::ExportEvents::CACHE_TTL_EXTENDED,
              {
                correlation_id: correlation_id,
            extension_duration: extension_duration,
                new_ttl: result[:new_ttl],
                timestamp: Time.current
          }
            )

          log_structured(
            :info,
              'Cache TTL extended successfully',
              entity_type: 'cache_coordination',
              entity_id: correlation_id,
              extension_duration: extension_duration,
              new_ttl: result[:new_ttl]
            )
          else
            log_structured(
              :warn,
              'Failed to extend cache TTL',
              entity_type: 'cache_coordination',
            entity_id: correlation_id,
              extension_duration: extension_duration,
              error: result[:error]
          )
          end

          result
        rescue StandardError => e
          log_structured(
            :error,
            'Cache TTL extension exception',
            entity_type: 'cache_coordination',
            entity_id: correlation_id,
            extension_duration: extension_duration,
            error: e.message,
            error_class: e.class.name
          )

          { success: false, error: e.message }
        end
      end

      private

      # Publish event to the event bus
      #
      # @param event_name [String] Event name
      # @param payload [Hash] Event payload
      def publish_event(event_name, payload)
        @event_bus.publish(event_name, payload)
      rescue StandardError => e
        log_structured(:warn, 'Failed to publish export event',
                       event_name: event_name,
                       error: e.message,
                       error_class: e.class.name)
      end

      # Notify all registered plugins of an event
      #
      # @param method_name [Symbol] Method to call on plugins
      # @param data [Hash] Data to pass to plugins
      def notify_plugins(method_name, data)
        @plugin_registry.all_plugins.each do |name, plugin_config|
          plugin = plugin_config[:instance]

          if plugin.respond_to?(method_name)
          begin
            plugin.send(method_name, data)
          rescue StandardError => e
              log_structured(:warn, 'Plugin notification failed',
                             plugin_name: name,
                           plugin_class: plugin.class.name,
                             method_name: method_name,
                           error: e.message,
                             error_class: e.class.name)
            end
          end
        end
      end

      # Coordinate plugin-based export using PluginRegistry
      #
      # @param format [Symbol] Export format
      # @param metrics_data [Hash] Metrics data to export
      # @param correlation_id [String] Correlation ID for tracking
      # @return [Hash] Export result
      def coordinate_plugin_export(format, metrics_data, correlation_id)
        plugins = plugins_for_format(format)

        if plugins.empty?
          return {
            success: false,
            error: "No plugins available for format: #{format}"
          }
        end

        # Try each plugin until one succeeds
        plugins.each do |plugin|
          begin
            plugin_result = plugin.export(metrics_data, { correlation_id: correlation_id })

            if plugin_result[:success]
              log_structured(:debug, 'Plugin export successful',
                             plugin_class: plugin.class.name,
                             format: format,
                             correlation_id: correlation_id)
              return plugin_result
            else
              log_structured(:warn, 'Plugin export failed',
                             plugin_class: plugin.class.name,
                             format: format,
                             error: plugin_result[:error],
                             correlation_id: correlation_id)
            end
          rescue StandardError => e
            log_structured(:error, 'Plugin export exception',
                           plugin_class: plugin.class.name,
              format: format,
              error: e.message,
                           error_class: e.class.name,
                           correlation_id: correlation_id)
          end
        end

        {
          success: false,
          error: "All plugins failed for format: #{format}"
        }
      end
    end
  end
end
