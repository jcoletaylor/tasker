# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Telemetry::ExportCoordinator do
  let(:coordinator) { described_class.instance }
  let(:event_bus) { Tasker::Events::Publisher.instance }

  # Create a proper mock plugin class that meets interface requirements
  let(:mock_plugin_class) do
    Class.new do
      def export(metrics_data, _options = {})
        { success: true, format: 'mock', data: metrics_data }
      end

      def supports_format?(format)
        format.to_s == 'mock'
      end

      def supported_formats
        ['mock']
      end

      def on_cache_sync(sync_data)
        # Optional callback
      end

      def self.name
        'MockPlugin'
      end
    end
  end

  let(:mock_plugin) { mock_plugin_class.new }

  before do
    # Clear any existing plugins
    coordinator.registered_plugins.each_key do |plugin_name|
      coordinator.unregister_plugin(plugin_name)
    end
  end

  describe '#register_plugin' do
    it 'registers a valid plugin successfully' do
      result = coordinator.register_plugin('test_plugin', mock_plugin)

      expect(result).to be true
      expect(coordinator.registered_plugins).to have_key('test_plugin')
    end

    it 'validates plugin interface before registration' do
      invalid_plugin = Object.new
      # This plugin is missing both required methods

      expect do
        coordinator.register_plugin('invalid', invalid_plugin)
      end.to raise_error(ArgumentError, /must implement export method/)
    end

    it 'validates export method arity' do
      invalid_plugin_class = Class.new do
        def export
          # No parameters - should fail validation
        end

        def supports_format?(_format)
          true
        end

        def self.name
          'InvalidPlugin'
        end
      end

      expect do
        coordinator.register_plugin('invalid', invalid_plugin_class.new)
      end.to raise_error(ArgumentError, /must accept at least one argument/)
    end

    it 'allows plugins to be replaced' do
      coordinator.register_plugin('test_plugin', mock_plugin)

      new_plugin_class = Class.new do
        def export(metrics_data, _options = {})
          { success: true, format: 'new', data: metrics_data }
        end

        def supports_format?(format)
          format.to_s == 'new'
        end

        def self.name
          'NewPlugin'
        end
      end

      new_plugin = new_plugin_class.new
      result = coordinator.register_plugin('test_plugin', new_plugin)

      expect(result).to be true
      expect(coordinator.registered_plugins['test_plugin'][:instance]).to eq(new_plugin)
    end

    it 'publishes plugin registered event' do
      expect(event_bus).to receive(:publish).with(
        Tasker::Telemetry::Events::ExportEvents::PLUGIN_REGISTERED,
        hash_including(
          plugin_name: 'test_plugin',
          plugin_class: 'MockPlugin'
        )
      )

      coordinator.register_plugin('test_plugin', mock_plugin)
    end
  end

  describe '#coordinate_cache_sync' do
    let(:sync_result) do
      {
        strategy: :distributed_atomic,
        metrics_count: 42,
        duration_ms: 150.5,
        success: true
      }
    end

    before do
      coordinator.register_plugin('test_plugin', mock_plugin)
    end

    it 'publishes cache synced event' do
      expect(event_bus).to receive(:publish).with(
        Tasker::Telemetry::Events::ExportEvents::CACHE_SYNCED,
        hash_including(
          strategy: :distributed_atomic,
          metrics_count: 42,
          duration_ms: 150.5,
          success: true
        )
      )

      coordinator.coordinate_cache_sync(sync_result)
    end

    it 'notifies plugins with cache sync data' do
      # Spy on the plugin to verify it receives the callback
      allow(mock_plugin).to receive(:on_cache_sync)

      coordinator.coordinate_cache_sync(sync_result)

      expect(mock_plugin).to have_received(:on_cache_sync).with(sync_result)
    end
  end
end
