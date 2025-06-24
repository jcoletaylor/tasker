# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Telemetry::MetricsExportService do
  let(:service) { described_class.new(config) }
  let(:config) { {} }

  let(:sample_metrics_data) do
    {
      metadata: {
        collection_time: Time.current.iso8601,
        instance_id: 'test-instance',
        version: '1.0.0'
      },
      metrics: {
        'task_count' => { type: :counter, value: 42 },
        'active_connections' => { type: :gauge, value: 15 },
        'response_time' => {
          type: :histogram,
          sum: 2500,
          count: 100,
          buckets: { '0.1' => 10, '0.5' => 25, '1.0' => 50, '+Inf' => 100 }
        }
      }
    }
  end

  let(:export_context) do
    {
      job_id: 'test-job-123',
      coordinator_instance: 'web-1-12345',
      scheduled_by: 'coordinator'
    }
  end

  describe '#initialize' do
    it 'uses default configuration when none provided' do
      service = described_class.new

      expect(service.config).to include(
        storage_root: Rails.root.join('tmp/metrics_exports'),
        prometheus_config: kind_of(Hash)
      )
    end

    it 'merges provided configuration with defaults' do
      custom_config = {
        storage_root: '/custom/path',
        prometheus_config: { endpoint: 'http://test.com' }
      }

      service = described_class.new(custom_config)

      expect(service.config[:storage_root]).to eq('/custom/path')
      expect(service.config[:prometheus_config][:endpoint]).to eq('http://test.com')
    end
  end

  describe '#export_metrics' do
    it 'exports metrics in json format successfully' do
      allow(File).to receive(:write)
      allow(FileUtils).to receive(:mkdir_p)

      result = service.export_metrics(
        format: :json,
        metrics_data: sample_metrics_data,
        context: export_context
      )

      expect(result).to include(
        success: true,
        format: :json,
        storage: hash_including(success: true, storage_type: 'filesystem'),
        data_length: kind_of(Numeric)
      )
    end

    it 'returns error for unsupported format' do
      result = service.export_metrics(
        format: :xml,
        metrics_data: sample_metrics_data,
        context: export_context
      )

      expect(result).to include(
        success: false,
        error: 'Unsupported export format: xml',
        supported_formats: %i[prometheus json csv]
      )
    end

    it 'handles export errors gracefully' do
      allow(service).to receive(:export_json_metrics).and_raise(StandardError, 'Test error')

      result = service.export_metrics(
        format: :json,
        metrics_data: sample_metrics_data,
        context: export_context
      )

      expect(result).to include(
        success: false,
        error: 'Test error',
        error_type: 'StandardError'
      )
    end
  end
end
