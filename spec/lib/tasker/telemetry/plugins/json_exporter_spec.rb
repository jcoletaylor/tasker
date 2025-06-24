# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Telemetry::Plugins::JsonExporter do
  let(:exporter) { described_class.new }
  let(:sample_metrics_data) do
    {
      timestamp: '2023-06-23T10:39:42Z',
      total_metrics: 2,
      metrics: {
        'api_requests_total' => {
          name: 'api_requests_total',
          type: :counter,
          value: 125,
          labels: { method: 'GET', status: 'success' }
        },
        'active_connections' => {
          name: 'active_connections',
          type: :gauge,
          value: 5,
          labels: {}
        }
      }
    }
  end

  describe '#export' do
    it 'exports metrics as JSON' do
      result = exporter.export(sample_metrics_data)

      expect(result[:success]).to be true
      expect(result[:format]).to eq('json')
      expect(result[:size_bytes]).to be > 0
      expect(result[:metrics_count]).to eq(2)

      # Parse the JSON to verify structure
      json_data = JSON.parse(result[:data])
      expect(json_data['timestamp']).to eq('2023-06-23T10:39:42Z')
      expect(json_data['total_metrics']).to eq(2)
      expect(json_data['metrics']).to have_key('api_requests_total')
    end

    it 'supports pretty printing' do
      result = exporter.export(sample_metrics_data, pretty: true)

      expect(result[:success]).to be true
      expect(result[:data]).to include("\n") # Pretty printed JSON has newlines
    end

    it 'includes metadata by default' do
      result = exporter.export(sample_metrics_data)

      json_data = JSON.parse(result[:data])
      expect(json_data['metadata']).to be_present
      expect(json_data['metadata']['exporter']).to eq('json')
      expect(json_data['metadata']['version']).to eq('1.0.0')
    end

    it 'can exclude metadata' do
      exporter_without_metadata = described_class.new(include_metadata: false)
      result = exporter_without_metadata.export(sample_metrics_data)

      json_data = JSON.parse(result[:data])
      expect(json_data).not_to have_key('metadata')
    end

    it 'supports custom field mapping' do
      custom_exporter = described_class.new(
        field_mapping: {
          timestamp: 'collected_at',
          metrics: 'data',
          total_metrics: 'count'
        }
      )

      result = custom_exporter.export(sample_metrics_data)

      json_data = JSON.parse(result[:data])
      expect(json_data).to have_key('collected_at')
      expect(json_data).to have_key('data')
      expect(json_data).to have_key('count')
      expect(json_data).not_to have_key('timestamp')
      expect(json_data).not_to have_key('metrics')
    end

    it 'supports additional fields' do
      result = exporter.export(sample_metrics_data, additional_fields: {
                                 environment: 'test',
                                 service: 'tasker'
                               })

      json_data = JSON.parse(result[:data])
      expect(json_data['environment']).to eq('test')
      expect(json_data['service']).to eq('tasker')
    end
  end

  describe '#supports_format?' do
    it 'supports json format' do
      expect(exporter.supports_format?('json')).to be true
      expect(exporter.supports_format?('JSON')).to be true
    end

    it 'does not support other formats' do
      expect(exporter.supports_format?('csv')).to be false
      expect(exporter.supports_format?('xml')).to be false
    end
  end

  describe '#supported_formats' do
    it 'returns json as supported format' do
      expect(exporter.supported_formats).to eq(['json'])
    end
  end

  describe 'metric formatting' do
    it 'formats metrics with all fields' do
      result = exporter.export(sample_metrics_data)
      json_data = JSON.parse(result[:data])

      metric = json_data['metrics']['api_requests_total']
      expect(metric['name']).to eq('api_requests_total')
      expect(metric['type']).to eq('counter')
      expect(metric['value']).to eq(125)
      expect(metric['labels']).to eq({ 'method' => 'GET', 'status' => 'success' })
    end

    it 'handles metrics without labels' do
      result = exporter.export(sample_metrics_data)
      json_data = JSON.parse(result[:data])

      metric = json_data['metrics']['active_connections']
      expect(metric['labels']).to eq({})
    end

    it 'handles empty metrics gracefully' do
      empty_data = sample_metrics_data.merge(metrics: {}, total_metrics: 0)
      result = exporter.export(empty_data)

      json_data = JSON.parse(result[:data])
      expect(json_data['metrics']).to eq({})
    end
  end

  describe 'error handling' do
    it 'handles malformed metrics data' do
      invalid_data = {
        timestamp: 'invalid',
        metrics: 'not a hash',
        total_metrics: 'not a number'
      }

      expect do
        exporter.export(invalid_data)
      end.not_to raise_error
    end
  end

  describe 'constants' do
    it 'defines version constant' do
      expect(described_class::VERSION).to eq('1.0.0')
    end

    it 'defines description constant' do
      expect(described_class::DESCRIPTION).to be_present
    end
  end
end
