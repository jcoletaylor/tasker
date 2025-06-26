# frozen_string_literal: true

require_relative '../registry/base_registry'
require_relative '../registry/interface_validator'
require 'concurrent-ruby'

module Tasker
  module Telemetry
    # Registry for managing export plugins
    #
    # Provides centralized management of export plugins with discovery,
    # registration, and format-based lookup capabilities. Now modernized
    # with BaseRegistry patterns for consistency across all registry systems.
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
    class PluginRegistry < Registry::BaseRegistry
      include Singleton

      def initialize
        super
        @plugins = Concurrent::Hash.new
        @formats = Concurrent::Hash.new
        log_registry_operation('initialized', total_plugins: 0, total_formats: 0)
      end

      # Register a plugin
      #
      # @param name [String, Symbol] Plugin identifier
      # @param plugin [Object] Plugin instance
      # @param replace [Boolean] Whether to replace existing plugin
      # @param options [Hash] Plugin options
      # @return [Boolean] True if registration successful
      def register(name, plugin, replace: false, **options)
        name = name.to_s

        thread_safe_operation do
          # Validate plugin interface
          begin
            Registry::InterfaceValidator.validate_plugin!(plugin)
          rescue ArgumentError => e
            log_validation_failure('telemetry_plugin', name, e.message)
            raise
          end

          # Check for existing plugin
          if @plugins.key?(name) && !replace
            raise ArgumentError, "Plugin '#{name}' already registered. Use replace: true to override."
          end

          # Remove existing plugin if replacing
          if @plugins.key?(name)
            existing_config = @plugins[name]
            unregister_format_mappings(name, existing_config[:supported_formats])
            log_unregistration('telemetry_plugin', name, existing_config[:instance].class)
          end

          # Get supported formats
          supported_formats = get_supported_formats(plugin)

          # Register plugin
          plugin_config = {
            instance: plugin,
            name: name,
            options: options.merge(replace: replace),
            registered_at: Time.current,
            supported_formats: supported_formats
          }

          @plugins[name] = plugin_config

          # Index by supported formats
          register_format_mappings(name, supported_formats)

          log_registration('telemetry_plugin', name, plugin.class,
                          { supported_formats: supported_formats, format_count: supported_formats.size, **options })

          true
        end
      end

      # Unregister a plugin
      #
      # @param name [String, Symbol] Plugin identifier
      # @return [Boolean] True if unregistered successfully
      def unregister(name)
        name = name.to_s

        thread_safe_operation do
          plugin_config = @plugins.delete(name)

          if plugin_config
            # Remove from format index
            unregister_format_mappings(name, plugin_config[:supported_formats])

            log_unregistration('telemetry_plugin', name, plugin_config[:instance].class)
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

      # Get all registered plugins (required by BaseRegistry)
      #
      # @return [Hash] All registered plugins
      def all_items
        all_plugins
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
        @formats.key?(format.to_s.downcase)
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
          begin
            require file

            # Extract class name from filename
            class_name = File.basename(file, '.rb').camelize
            full_class_name = "Tasker::Telemetry::Plugins::#{class_name}"

            # Try to instantiate the plugin
            plugin_class = full_class_name.constantize
            plugin_instance = plugin_class.new

            register(class_name.underscore, plugin_instance, auto_discovered: true)
            discovered_count += 1

            log_registry_operation('auto_discovered_plugin',
                                   plugin_name: class_name,
                                   plugin_class: full_class_name,
                                   file_path: file)
          rescue StandardError => e
            log_registry_error('auto_discovery_failed', e,
                               file_path: file,
                               class_name: File.basename(file, '.rb').camelize)
          end
        end

        discovered_count
      end

      # Get comprehensive registry statistics
      #
      # @return [Hash] Detailed statistics about the registry
      def stats
        base_stats.merge(
          total_plugins: @plugins.size,
          total_formats: @formats.size,
          supported_formats: @formats.keys.sort,
          plugins_by_format: @formats.transform_values(&:size),
          average_formats_per_plugin: calculate_average_formats_per_plugin,
          most_popular_formats: find_most_popular_formats,
          plugin_distribution: calculate_plugin_distribution
        )
      end

      # Clear all registered plugins (required by BaseRegistry)
      #
      # @return [Boolean] True if cleared successfully
      def clear!
        thread_safe_operation do
          @plugins.clear
          @formats.clear
          log_registry_operation('cleared_all')
          true
        end
      end

      # Legacy method for backward compatibility
      #
      # @return [Boolean] True if cleared successfully
      def clear_all!
        clear!
      end

      private

      # Register format mappings for a plugin
      #
      # @param plugin_name [String] Name of the plugin
      # @param formats [Array<String>] Formats to map
      def register_format_mappings(plugin_name, formats)
        formats.each do |format|
          format_key = format.to_s.downcase
          @formats[format_key] ||= []
          @formats[format_key] << plugin_name unless @formats[format_key].include?(plugin_name)
        end
      end

      # Unregister format mappings for a plugin
      #
      # @param plugin_name [String] Name of the plugin
      # @param formats [Array<String>] Formats to unmap
      def unregister_format_mappings(plugin_name, formats)
        formats.each do |format|
          format_key = format.to_s.downcase
          @formats[format_key]&.delete(plugin_name)
          @formats.delete(format_key) if @formats[format_key] && @formats[format_key].empty?
        end
      end

      # Get supported formats from a plugin
      #
      # @param plugin [Object] Plugin instance
      # @return [Array<String>] Array of supported formats
      def get_supported_formats(plugin)
        return [] unless plugin.respond_to?(:supported_formats)

        formats = plugin.supported_formats
        Array(formats).map(&:to_s).map(&:downcase).uniq
      rescue StandardError => e
        log_registry_error('format_discovery_failed', e,
                           plugin_class: plugin.class.name)
        []
      end

      # Calculate average formats per plugin
      #
      # @return [Float] Average number of formats per plugin
      def calculate_average_formats_per_plugin
        return 0.0 if @plugins.empty?

        total_formats = @plugins.values.sum { |config| config[:supported_formats].size }
        (total_formats.to_f / @plugins.size).round(2)
      end

      # Find the most popular formats (top 5)
      #
      # @return [Array<Hash>] Array of format popularity data
      def find_most_popular_formats
        @formats
          .map { |format, plugins| { format: format, plugin_count: plugins.size } }
          .sort_by { |data| -data[:plugin_count] }
          .first(5)
      end

      # Calculate plugin distribution statistics
      #
      # @return [Hash] Distribution statistics
      def calculate_plugin_distribution
        formats_per_plugin = @plugins.values.map { |config| config[:supported_formats].size }

        return { distribution: 'empty' } if formats_per_plugin.empty?

        {
          distribution: calculate_distribution_type(formats_per_plugin),
          average_formats_per_plugin: calculate_average_formats_per_plugin,
          max_formats_per_plugin: formats_per_plugin.max,
          min_formats_per_plugin: formats_per_plugin.min
        }
      end

      # Calculate distribution type based on formats per plugin
      #
      # @param formats_per_plugin [Array<Integer>] Array of format counts
      # @return [String] Distribution type
      def calculate_distribution_type(formats_per_plugin)
        return 'empty' if formats_per_plugin.empty?
        return 'uniform' if formats_per_plugin.uniq.size == 1

        avg = formats_per_plugin.sum.to_f / formats_per_plugin.size
        variance = formats_per_plugin.sum { |count| (count - avg)**2 } / formats_per_plugin.size

        variance < 2 ? 'even' : 'varied'
      end
    end
  end
end
