# frozen_string_literal: true

require 'concurrent-ruby'

module Tasker
  module Telemetry
    # Registry for managing export plugins
    #
    # Provides centralized management of export plugins with discovery,
    # registration, and format-based lookup capabilities.
    #
    # @example Register a plugin
    #   registry = Tasker::Telemetry::PluginRegistry.instance
    #   registry.register('my_exporter', MyExporter.new)
    #
    # @example Find plugins by format
    #   json_plugins = registry.find_by_format('json')
    #   csv_plugins = registry.find_by_format('csv')
    #
    # @example Auto-discover plugins
    #   registry.auto_discover_plugins
    class PluginRegistry
      include Singleton
      include Tasker::Concerns::StructuredLogging

      def initialize
        @plugins = Concurrent::Hash.new
        @formats = Concurrent::Hash.new
        @mutex = Mutex.new
      end

      # Register a plugin
      #
      # @param name [String, Symbol] Plugin identifier
      # @param plugin [Object] Plugin instance
      # @param options [Hash] Plugin options
      def register(name, plugin, options = {})
        name = name.to_s
        replace = options.fetch(:replace, false)

        # Validate plugin interface
        validate_plugin!(plugin)

        @mutex.synchronize do
          # Check for existing plugin
          if @plugins.key?(name) && !replace
            raise ArgumentError, "Plugin '#{name}' already registered. Use replace: true to override."
          end

          # Remove existing plugin if replacing (avoid recursive mutex call)
          if @plugins.key?(name)
            existing_config = @plugins.delete(name)

            # Remove from format index
            existing_config[:supported_formats].each do |format|
              @formats[format]&.delete(name)
              @formats.delete(format) if @formats[format] && @formats[format].empty?
            end

            log_structured(:info, 'Plugin unregistered for replacement',
                           entity_type: 'telemetry_plugin',
                           entity_id: name,
                           plugin_name: name,
                           plugin_class: existing_config[:instance].class.name,
                           event_type: :unregistered_for_replacement)
          end

          # Register plugin
          plugin_config = {
            instance: plugin,
            name: name,
            options: options,
            registered_at: Time.current,
            supported_formats: get_supported_formats(plugin)
          }

          @plugins[name] = plugin_config

          # Index by supported formats
          plugin_config[:supported_formats].each do |format|
            @formats[format] ||= []
            @formats[format] << name
          end

          log_structured(:info, 'Plugin registered',
                         entity_type: 'telemetry_plugin',
                         entity_id: name,
                         plugin_name: name,
                         plugin_class: plugin.class.name,
                         supported_formats: plugin_config[:supported_formats],
                         options: options,
                         event_type: :registered)

          true
        end
      end

      # Unregister a plugin
      #
      # @param name [String, Symbol] Plugin identifier
      # @return [Boolean] True if unregistered successfully
      def unregister(name)
        name = name.to_s

        @mutex.synchronize do
          plugin_config = @plugins.delete(name)

          if plugin_config
            # Remove from format index
            plugin_config[:supported_formats].each do |format|
              @formats[format]&.delete(name)
              @formats.delete(format) if @formats[format] && @formats[format].empty?
            end

            log_structured(:info, 'Plugin unregistered',
                           entity_type: 'telemetry_plugin',
                           entity_id: name,
                           plugin_name: name,
                           plugin_class: plugin_config[:instance].class.name,
                           event_type: :unregistered)

            true
          else
            false
          end
        end
      end

      # Get all registered plugins
      #
      # @return [Hash] Hash of plugin name => plugin info
      def all_plugins
        @plugins.dup
      end

      # Get plugin by name
      #
      # @param name [String, Symbol] Plugin identifier
      # @return [Object, nil] Plugin instance or nil if not found
      def get_plugin(name)
        plugin_config = @plugins[name.to_s]
        plugin_config&.dig(:instance)
      end

      # Find plugins that support a specific format
      #
      # @param format [String, Symbol] Format to search for
      # @return [Array<Object>] Array of plugin instances
      def find_by_format(format)
        format = format.to_s.downcase
        plugin_names = @formats[format].to_a

        plugin_names.filter_map { |name| get_plugin(name) }
      end

      # Find plugins by criteria (supports keyword arguments for test compatibility)
      #
      # @param format [String, Symbol] Format to search for
      # @return [Array<Object>] Array of plugin instances
      def find_by(format:)
        find_by_format(format)
      end

      # Get supported formats across all plugins
      #
      # @return [Array<String>] Array of supported format names
      def supported_formats
        @formats.keys.sort
      end

      # Check if a format is supported by any plugin
      #
      # @param format [String, Symbol] Format to check
      # @return [Boolean] True if format is supported
      def supports_format?(format)
        @formats.key?(format.to_s)
      end

      # Auto-discover plugins in the plugins directory
      #
      # @param directory [String] Directory to search for plugins
      # @return [Integer] Number of plugins discovered
      def auto_discover_plugins(directory = nil)
        directory ||= File.join(File.dirname(__FILE__), 'plugins')

        return 0 unless Dir.exist?(directory)

        discovered_count = 0

        Dir.glob(File.join(directory, '*_exporter.rb')).each do |file|
          require file

          # Extract class name from filename
          class_name = File.basename(file, '.rb').camelize
          full_class_name = "Tasker::Telemetry::Plugins::#{class_name}"

          # Try to instantiate the plugin
          plugin_class = full_class_name.constantize
          plugin_instance = plugin_class.new

          # Register with auto-discovery prefix
          plugin_name = "auto_#{class_name.underscore}"
          register(plugin_name, plugin_instance, auto_discovered: true)

          discovered_count += 1
        rescue StandardError => e
          log_structured(:warn, 'Failed to auto-discover plugin',
                         entity_type: 'plugin_registry',
                         file_path: file,
                         error: e.message,
                         event_type: :discovery_failed)
        end

        log_structured(:info, 'Auto-discovery completed',
                       entity_type: 'plugin_registry',
                       directory: directory,
                       discovered_count: discovered_count,
                       event_type: :discovery_completed)

        discovered_count
      end

      # Get plugin statistics
      #
      # @return [Hash] Registry statistics
      def stats
        {
          total_plugins: @plugins.size,
          supported_formats: supported_formats.size,
          format_distribution: @formats.transform_values(&:size),
          plugins_by_class: @plugins.values.group_by { |p| p[:instance].class.name }.transform_values(&:size)
        }
      end

      # Clear all plugins (useful for testing)
      #
      # @return [Boolean] True if cleared successfully
      def clear_all!
        @mutex.synchronize do
          @plugins.clear
          @formats.clear
          log_structured(:info, 'Plugin registry cleared',
                         entity_type: 'plugin_registry',
                         event_type: :cleared)
          true
        end
      end

      private

      # Validate plugin implements required interface
      def validate_plugin!(plugin)
        required_methods = %i[export supports_format?]

        required_methods.each do |method|
          raise ArgumentError, "Plugin must implement #{method} method" unless plugin.respond_to?(method)
        end

        # Test supports_format? method
        begin
          plugin.supports_format?('test')
        rescue StandardError => e
          raise ArgumentError, "Plugin supports_format? method failed: #{e.message}"
        end

        true
      end

      # Get supported formats for a plugin
      def get_supported_formats(plugin)
        return [] unless plugin.respond_to?(:supported_formats)

        formats = plugin.supported_formats
        case formats
        when Array
          formats.map(&:to_s)
        when String, Symbol
          [formats.to_s]
        else
          # Fallback: test common formats
          %w[json csv prometheus].select do |format|
            plugin.supports_format?(format)
          rescue StandardError => e
            log_structured(:warn, 'Failed to get supported formats',
                           entity_type: 'telemetry_plugin',
                           plugin_class: plugin.class.name,
                           format: format,
                           error: e.message,
                           event_type: :format_check_failed)
            false
          end
        end
      end
    end
  end
end
