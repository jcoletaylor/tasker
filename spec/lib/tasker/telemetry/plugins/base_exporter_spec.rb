# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Telemetry::Plugins::BaseExporter do
  let(:test_exporter_class) do
    Class.new(described_class) do
      def export(_metrics_data, _options = {})
        { success: true, data: 'test_export' }
      end

      def supports_format?(format)
        format.to_s == 'test'
      end
    end
  end

  let(:exporter) { test_exporter_class.new }
  let(:valid_metrics_data) do
    {
      timestamp: '2023-06-23T10:39:42Z',
      total_metrics: 2,
      metrics: {
        'test_counter' => {
          name: 'test_counter',
          type: :counter,
          value: 42,
          labels: { status: 'success' }
        }
      }
    }
  end

  describe '#export' do
    it 'raises NotImplementedError in base class' do
      base_exporter = described_class.new

      expect do
        base_exporter.export(valid_metrics_data)
      end.to raise_error(NotImplementedError, /must implement #export method/)
    end

    it 'can be implemented by subclasses' do
      result = exporter.export(valid_metrics_data)

      expect(result).to eq({ success: true, data: 'test_export' })
    end
  end

  describe '#supports_format?' do
    it 'raises NotImplementedError in base class' do
      base_exporter = described_class.new

      expect do
        base_exporter.supports_format?('json')
      end.to raise_error(NotImplementedError, /must implement #supports_format\? method/)
    end

    it 'can be implemented by subclasses' do
      expect(exporter.supports_format?('test')).to be true
      expect(exporter.supports_format?('json')).to be false
    end
  end

  describe '#plugin_info' do
    it 'returns basic plugin metadata' do
      info = exporter.plugin_info

      expect(info[:name]).to be_present
      expect(info[:version]).to eq('unknown') # No VERSION constant defined
      expect(info[:supported_formats]).to eq([])
      expect(info[:description]).to be_nil
    end

    context 'with plugin constants defined' do
      let(:enhanced_exporter_class) do
        Class.new(described_class) do
          VERSION = '1.2.3'
          DESCRIPTION = 'Test exporter for specs'

          def export(_metrics_data, _options = {})
            { success: true }
          end

          def supports_format?(format)
            format.to_s == 'test'
          end

          def supported_formats
            %w[test custom]
          end
        end
      end

      let(:enhanced_exporter) { enhanced_exporter_class.new }

      it 'returns enhanced plugin metadata' do
        info = enhanced_exporter.plugin_info

        expect(info[:version]).to eq('1.2.3')
        expect(info[:description]).to eq('Test exporter for specs')
        expect(info[:supported_formats]).to eq(%w[test custom])
      end
    end
  end

  describe '#safe_export' do
    it 'wraps export with error handling and timing' do
      result = exporter.safe_export(valid_metrics_data)

      expect(result[:success]).to be true
      expect(result[:result]).to eq({ success: true, data: 'test_export' })
      expect(result[:duration_ms]).to be_a(Numeric)
      expect(result[:plugin]).to be_present
    end

    it 'validates metrics data structure' do
      invalid_data = { invalid: 'structure' }

      result = exporter.safe_export(invalid_data)

      expect(result[:success]).to be false
      expect(result[:error]).to include('must contain :metrics key')
    end

    it 'handles export exceptions gracefully' do
      failing_exporter_class = Class.new(described_class) do
        def export(_metrics_data, _options = {})
          raise StandardError, 'Export failed'
        end

        def supports_format?(_format)
          true
        end
      end

      failing_exporter = failing_exporter_class.new
      result = failing_exporter.safe_export(valid_metrics_data)

      expect(result[:success]).to be false
      expect(result[:error]).to eq('Export failed')
      expect(result[:duration_ms]).to be_a(Numeric)
    end
  end

  describe 'lifecycle callbacks' do
    it 'provides default implementations for lifecycle methods' do
      expect { exporter.on_cache_sync({}) }.not_to raise_error
      expect { exporter.on_export_request({}) }.not_to raise_error
      expect { exporter.on_export_complete({}) }.not_to raise_error
    end

    it 'allows subclasses to override lifecycle methods' do
      callback_exporter_class = Class.new(described_class) do
        attr_reader :cache_sync_called, :export_request_called, :export_complete_called

        def export(_metrics_data, _options = {})
          { success: true }
        end

        def supports_format?(_format)
          true
        end

        def on_cache_sync(sync_data)
          @cache_sync_called = sync_data
        end

        def on_export_request(request_data)
          @export_request_called = request_data
        end

        def on_export_complete(completion_data)
          @export_complete_called = completion_data
        end
      end

      callback_exporter = callback_exporter_class.new

      callback_exporter.on_cache_sync({ strategy: :test })
      callback_exporter.on_export_request({ format: 'test' })
      callback_exporter.on_export_complete({ success: true })

      expect(callback_exporter.cache_sync_called).to eq({ strategy: :test })
      expect(callback_exporter.export_request_called).to eq({ format: 'test' })
      expect(callback_exporter.export_complete_called).to eq({ success: true })
    end
  end

  describe 'data validation' do
    it 'validates hash structure' do
      expect do
        exporter.send(:validate_metrics_data!, 'not a hash')
      end.to raise_error(ArgumentError, /must be a Hash/)
    end

    it 'validates required keys' do
      expect do
        exporter.send(:validate_metrics_data!, { missing: 'metrics' })
      end.to raise_error(ArgumentError, /must contain :metrics key/)

      expect do
        exporter.send(:validate_metrics_data!, { metrics: {}, missing: 'timestamp' })
      end.to raise_error(ArgumentError, /must contain :timestamp key/)
    end

    it 'passes validation for valid data' do
      expect do
        exporter.send(:validate_metrics_data!, valid_metrics_data)
      end.not_to raise_error
    end
  end
end
