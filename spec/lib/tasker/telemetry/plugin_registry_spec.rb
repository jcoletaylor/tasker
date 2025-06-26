# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Telemetry::PluginRegistry do
  let(:registry) { described_class.instance }

  # Create proper mock plugin classes that meet interface requirements
  let(:mock_plugin_class) do
    Class.new do
      def export(metrics_data, _options = {})
        { success: true, format: 'json', data: metrics_data }
      end

      def supports_format?(format)
        format.to_s == 'json'
      end

      def supported_formats
        ['json']
      end

      def self.name
        'MockPlugin'
      end
    end
  end

  let(:mock_plugin) { mock_plugin_class.new }

  before do
    # Clear registry before each test
    registry.clear_all!
  end

  describe '#register' do
    it 'registers a valid plugin successfully' do
      result = registry.register('test_plugin', mock_plugin)

      expect(result).to be true
      expect(registry.all_plugins).to have_key('test_plugin')
    end

    it 'validates plugin interface before registration' do
      invalid_plugin = Object.new
      # This plugin is missing both required methods

      expect do
        registry.register('invalid', invalid_plugin)
      end.to raise_error(ArgumentError, /must implement instance method export/)
    end

    it 'allows plugins to be replaced' do
      registry.register('test_plugin', mock_plugin)

      new_plugin_class = Class.new do
        def export(metrics_data, _options = {})
          { success: true, format: 'xml', data: metrics_data }
        end

        def supports_format?(format)
          format.to_s == 'xml'
        end

        def supported_formats
          ['xml']
        end

        def self.name
          'NewPlugin'
        end
      end

      new_plugin = new_plugin_class.new
      result = registry.register('test_plugin', new_plugin, replace: true)

      expect(result).to be true
      expect(registry.all_plugins['test_plugin'][:instance]).to eq(new_plugin)
    end

    it 'updates format index when registering plugin' do
      registry.register('test_plugin', mock_plugin)

      json_plugins = registry.find_by(format: 'json')
      expect(json_plugins.size).to eq(1)
      expect(json_plugins.first).to eq(mock_plugin)
    end
  end

  describe '#unregister' do
    before do
      registry.register('test_plugin', mock_plugin)
    end

    it 'unregisters existing plugin successfully' do
      result = registry.unregister('test_plugin')

      expect(result).to be true
      expect(registry.all_plugins).not_to have_key('test_plugin')
    end

    it 'returns false for non-existent plugin' do
      result = registry.unregister('non_existent')

      expect(result).to be false
    end

    it 'removes plugin from format index' do
      registry.unregister('test_plugin')

      expect(registry.find_by(format: 'json')).to be_empty
    end
  end

  describe '#find_by_format' do
    let(:json_plugin_class) do
      Class.new do
        def export(metrics_data, _options = {})
          { success: true, format: 'json', data: metrics_data }
        end

        def supports_format?(format)
          format.to_s == 'json'
        end

        def supported_formats
          ['json']
        end

        def self.name
          'JsonPlugin'
        end
      end
    end

    let(:csv_plugin_class) do
      Class.new do
        def export(metrics_data, _options = {})
          { success: true, format: 'csv', data: metrics_data }
        end

        def supports_format?(format)
          format.to_s == 'csv'
        end

        def supported_formats
          ['csv']
        end

        def self.name
          'CsvPlugin'
        end
      end
    end

    let(:json_plugin) { json_plugin_class.new }
    let(:csv_plugin) { csv_plugin_class.new }

    before do
      registry.register('json_plugin', json_plugin)
      registry.register('csv_plugin', csv_plugin)
    end

    it 'finds plugins by supported format' do
      json_plugins = registry.find_by(format: 'json')
      csv_plugins = registry.find_by(format: 'csv')

      expect(json_plugins.size).to eq(1)
      expect(csv_plugins.size).to eq(1)
      expect(json_plugins.first).to eq(json_plugin)
      expect(csv_plugins.first).to eq(csv_plugin)
    end

    it 'returns empty array for unsupported format' do
      plugins = registry.find_by(format: 'unsupported')

      expect(plugins).to be_empty
    end

    it 'handles case-insensitive format matching' do
      plugins = registry.find_by(format: 'JSON')

      expect(plugins.size).to eq(1)
      expect(plugins.first).to eq(json_plugin)
    end
  end

  describe '#supported_formats' do
    let(:multi_format_plugin_class) do
      Class.new do
        def export(metrics_data, _options = {})
          { success: true, format: 'json', data: metrics_data }
        end

        def supports_format?(format)
          %w[json csv xml].include?(format.to_s)
        end

        def supported_formats
          %w[json csv xml]
        end

        def self.name
          'MultiFormatPlugin'
        end
      end
    end

    let(:multi_format_plugin) { multi_format_plugin_class.new }

    before do
      registry.register('multi_plugin', multi_format_plugin)
    end

    it 'returns all supported formats across plugins' do
      formats = registry.supported_formats

      expect(formats).to include('json', 'csv', 'xml')
    end

    it 'returns sorted format list' do
      formats = registry.supported_formats

      expect(formats).to eq(formats.sort)
    end
  end

  describe '#supports_format?' do
    before do
      registry.register('json_plugin', mock_plugin)
    end

    it 'returns true for supported format' do
      expect(registry.supports_format?('json')).to be true
    end

    it 'returns false for unsupported format' do
      expect(registry.supports_format?('xml')).to be false
    end
  end

  describe '#stats' do
    let(:json_plugin_class) do
      Class.new do
        def export(metrics_data, _options = {})
          { success: true, format: 'json', data: metrics_data }
        end

        def supports_format?(format)
          format.to_s == 'json'
        end

        def supported_formats
          ['json']
        end

        def self.name
          'JsonPlugin'
        end
      end
    end

    let(:csv_plugin_class) do
      Class.new do
        def export(metrics_data, _options = {})
          { success: true, format: 'csv', data: metrics_data }
        end

        def supports_format?(format)
          format.to_s == 'csv'
        end

        def supported_formats
          ['csv']
        end

        def self.name
          'CsvPlugin'
        end
      end
    end

    let(:json_plugin) { json_plugin_class.new }
    let(:csv_plugin) { csv_plugin_class.new }

    before do
      registry.register('json_plugin', json_plugin)
      registry.register('csv_plugin', csv_plugin)
    end

    it 'returns comprehensive registry statistics' do
      stats = registry.stats

      expect(stats[:total_plugins]).to eq(2)
      expect(stats[:total_formats]).to eq(2)
      expect(stats[:supported_formats]).to eq(['csv', 'json'])
      expect(stats[:plugins_by_format]).to eq({ 'json' => 1, 'csv' => 1 })
      expect(stats[:average_formats_per_plugin]).to eq(1.0)
    end
  end

  describe '#auto_discover_plugins' do
    it 'discovers plugins in specified directory' do
      # Create a temporary directory with a valid plugin file
      Dir.mktmpdir do |temp_dir|
        plugin_file = File.join(temp_dir, 'test_exporter.rb')
        File.write(plugin_file, <<~RUBY)
          class TestExporter
            def export(data, options = {}); { success: true }; end
            def supports_format?(format); format == 'test'; end
            def self.name; 'TestExporter'; end
          end

          # Auto-register the plugin
          Tasker::Telemetry::PluginRegistry.instance.register(
            'auto_test_exporter',
            TestExporter.new,
            auto_discovered: true
          )
        RUBY

        initial_count = registry.all_plugins.size
        registry.auto_discover_plugins(temp_dir)

        expect(registry.all_plugins.size).to eq(initial_count + 1)
        expect(registry.all_plugins).to have_key('auto_test_exporter')
      end
    end

    it 'handles discovery errors gracefully' do
      # Create a temporary directory with an invalid plugin file
      Dir.mktmpdir do |temp_dir|
        invalid_file = File.join(temp_dir, 'invalid_exporter.rb')
        File.write(invalid_file, 'invalid ruby code')

        expect do
          registry.auto_discover_plugins(temp_dir)
        end.not_to raise_error
      end
    end

    it 'returns 0 for non-existent directory' do
      expect do
        registry.auto_discover_plugins('/non/existent/directory')
      end.not_to raise_error
    end
  end

  describe 'thread safety' do
    it 'handles concurrent plugin registration safely' do
      threads = []

      10.times do |i|
        threads << Thread.new do
          plugin_class = Class.new do
            define_method(:export) { |_data, _options = {}| { success: true } }
            define_method(:supports_format?) { |_format| false }
            define_method(:supported_formats) { [] }
            define_singleton_method(:name) { "Plugin#{i}" }
          end

          registry.register("plugin_#{i}", plugin_class.new)
        end
      end

      threads.each(&:join)

      expect(registry.all_plugins.size).to eq(10)
    end
  end
end
