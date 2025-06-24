# frozen_string_literal: true

require 'concurrent-ruby'
require 'securerandom'

module Tasker
  module Telemetry
    # ExportCoordinator manages plugin registration and coordinates export events
    class ExportCoordinator
      include Singleton
      include Tasker::Concerns::StructuredLogging

      def initialize
        @plugins = Concurrent::Hash.new
        @event_bus = Tasker::Events::Publisher.instance
        @mutex = Mutex.new
      end

      # Register a plugin for export coordination
      #
      # @param name [String, Symbol] Plugin identifier
      # @param plugin [Object] Plugin instance implementing required interface
      # @param options [Hash] Plugin configuration options
      def register_plugin(name, plugin, options = {})
        validate_plugin!(plugin)

        @mutex.synchronize do
          plugin_config = {
            instance: plugin,
            name: name.to_s,
            options: options,
            registered_at: Time.current
          }

          @plugins[name.to_s] = plugin_config

          log_structured(:info, 'Export plugin registered',
                         entity_type: 'export_plugin',
                         entity_id: name.to_s,
                         plugin_name: name.to_s,
                         plugin_class: plugin.class.name,
                         options: options,
                         event_type: :registered)

          publish_event(Events::ExportEvents::PLUGIN_REGISTERED, {
                          plugin_name: name.to_s,
                          plugin_class: plugin.class.name,
                          options: options,
                          timestamp: Time.current.iso8601
                        })
        end

        true
      end

      # Unregister a plugin
      #
      # @param name [String, Symbol] Plugin identifier
      def unregister_plugin(name)
        @mutex.synchronize do
          plugin_config = @plugins.delete(name.to_s)

          if plugin_config
            log_structured(:info, 'Export plugin unregistered',
                           entity_type: 'export_plugin',
                           entity_id: name.to_s,
                           plugin_name: name.to_s,
                           plugin_class: plugin_config[:instance].class.name,
                           event_type: :unregistered)

            publish_event(Events::ExportEvents::PLUGIN_UNREGISTERED, {
                            plugin_name: name.to_s,
                            plugin_class: plugin_config[:instance].class.name,
                            timestamp: Time.current.iso8601
                          })

            true
          else
            false
          end
        end
      end

      # Get registered plugins
      #
      # @return [Hash] Registered plugins
      def registered_plugins
        @plugins.dup
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

          # Coordinate with registered plugins
          coordinate_plugin_export(format, metrics_data, correlation_id)

          # Build result
          result = {
            success: true,
            result: {
              metrics: metrics_data,
              metadata: {
                export_time: start_time,
                format: format,
                include_instances: include_instances,
                correlation_id: correlation_id,
                instance_id: metrics_backend.instance_id
              }
            },
            timing: {
              export_time: start_time,
              duration: Time.current - start_time
            }
          }

          # Publish export completed event
          @event_bus.publish(
            Tasker::Telemetry::Events::ExportEvents::EXPORT_COMPLETED,
            {
              correlation_id: correlation_id,
              format: format,
              success: true,
              duration: result[:timing][:duration],
              metrics_count: metrics_data.size,
              timestamp: Time.current
            }
          )

          log_structured(
            :info,
            'Coordinated export completed successfully',
            entity_type: 'export_coordination',
            entity_id: correlation_id,
            format: format,
            duration: result[:timing][:duration],
            metrics_count: metrics_data.size
          )

          result
        rescue StandardError => e
          # Publish export failed event
          @event_bus.publish(
            Tasker::Telemetry::Events::ExportEvents::EXPORT_FAILED,
            {
              correlation_id: correlation_id,
              format: format,
              error: e.message,
              error_class: e.class.name,
              timestamp: Time.current
            }
          )

          log_structured(
            :error,
            'Coordinated export failed',
            entity_type: 'export_coordination',
            entity_id: correlation_id,
            format: format,
            error: e.message,
            error_class: e.class.name,
            duration: Time.current - start_time
          )

          {
            success: false,
            error: e.message,
            error_class: e.class.name,
            correlation_id: correlation_id
          }
        end
      end

      # Extend cache TTL for metrics data (used during retries)
      #
      # @param extension_duration [Integer] Duration in seconds to extend TTL
      # @return [Hash] Result with success status and metrics extended count
      def extend_cache_ttl(extension_duration)
        correlation_id = SecureRandom.uuid

        log_structured(
          :info,
          'Extending cache TTL for metrics',
          entity_type: 'cache_ttl_extension',
          entity_id: correlation_id,
          extension_duration: extension_duration
        )

        begin
          metrics_backend = Tasker::Telemetry::MetricsBackend.instance

          # For now, return a success response since our current implementation
          # uses in-memory storage with Rails.cache sync
          # In a full distributed implementation, this would extend TTL for cache keys

          result = {
            success: true,
            metrics_extended: metrics_backend.export_metrics.size,
            extension_duration: extension_duration,
            correlation_id: correlation_id
          }

          log_structured(
            :info,
            'Cache TTL extension completed',
            entity_type: 'cache_ttl_extension',
            entity_id: correlation_id,
            metrics_extended: result[:metrics_extended],
            extension_duration: extension_duration
          )

          result
        rescue StandardError => e
          log_structured(
            :error,
            'Cache TTL extension failed',
            entity_type: 'cache_ttl_extension',
            entity_id: correlation_id,
            error: e.message,
            error_class: e.class.name,
            extension_duration: extension_duration
          )

          {
            success: false,
            error: e.message,
            error_class: e.class.name,
            correlation_id: correlation_id
          }
        end
      end

      private

      # Validate plugin implements required interface
      def validate_plugin!(plugin)
        required_methods = %i[export supports_format?]

        required_methods.each do |method|
          raise ArgumentError, "Plugin must implement #{method} method" unless plugin.respond_to?(method)
        end

        # Validate export method signature
        export_method = plugin.method(:export)

        # Check if method accepts at least one argument
        # Positive arity = exact number of required args
        # Negative arity = -(required_args + 1), so -1 means 0+ args, -2 means 1+ args, etc.
        min_required_args = export_method.arity >= 0 ? export_method.arity : export_method.arity.abs - 1

        if min_required_args < 1
          raise ArgumentError, 'Plugin export method must accept at least one argument (metrics_data)'
        end

        true
      end

      # Publish event to event bus
      def publish_event(event_name, payload)
        @event_bus.publish(event_name, payload)
      rescue StandardError => e
        log_structured(:error, 'Failed to publish export event',
                       entity_type: 'export_coordinator',
                       event_type: :publish_failed,
                       event_name: event_name,
                       error: e.message,
                       backtrace: e.backtrace&.first(5))
      end

      # Notify all plugins of an event
      def notify_plugins(method_name, data)
        @plugins.each_value do |plugin_config|
          plugin = plugin_config[:instance]

          next unless plugin.respond_to?(method_name)

          begin
            plugin.send(method_name, data)
          rescue StandardError => e
            log_structured(:error, 'Plugin notification failed',
                           entity_type: 'export_plugin',
                           entity_id: plugin_config[:name],
                           plugin_name: plugin_config[:name],
                           plugin_class: plugin.class.name,
                           method: method_name,
                           error: e.message,
                           event_type: :notification_failed)
          end
        end
      end

      # Coordinate export with registered plugins
      def coordinate_plugin_export(format, metrics_data, correlation_id)
        @plugins.each do |name, plugin_config|
          plugin = plugin_config[:instance]

          begin
            # Check if plugin supports this format
            next unless plugin.supports_format?(format)

            # Call plugin lifecycle callback if available
            plugin.on_export_request(format, metrics_data, correlation_id) if plugin.respond_to?(:on_export_request)

            log_structured(
              :debug,
              'Plugin coordinated for export',
              entity_type: 'plugin_coordination',
              entity_id: correlation_id,
              plugin_name: name,
              format: format
            )
          rescue StandardError => e
            log_structured(
              :warn,
              'Plugin coordination failed',
              entity_type: 'plugin_coordination',
              entity_id: correlation_id,
              plugin_name: name,
              format: format,
              error: e.message,
              error_class: e.class.name
            )
          end
        end
      end
    end
  end
end
