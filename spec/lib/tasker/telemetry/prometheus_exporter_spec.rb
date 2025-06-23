# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Telemetry::PrometheusExporter do
  let(:backend) { instance_double(Tasker::Telemetry::MetricsBackend) }
  let(:exporter) { described_class.new(backend) }

  around do |example|
    # Store original configuration
    original_config = Tasker.configuration.dup

    # Configure telemetry for tests
    Tasker.configure do |config|
      config.telemetry do |telemetry|
        telemetry.metrics_enabled = true
      end
    end

    example.run

    # Restore original configuration
    Tasker.instance_variable_set(:@configuration, original_config)
  end

  describe '#initialize' do
    it 'uses MetricsBackend singleton by default' do
      default_exporter = described_class.new
      expect(default_exporter.instance_variable_get(:@backend)).to eq(Tasker::Telemetry::MetricsBackend.instance)
    end

    it 'accepts custom backend' do
      custom_backend = instance_double(Tasker::Telemetry::MetricsBackend)
      custom_exporter = described_class.new(custom_backend)
      expect(custom_exporter.instance_variable_get(:@backend)).to eq(custom_backend)
    end
  end

  describe '#export' do
    context 'when telemetry is disabled' do
      around do |example|
        Tasker.configure do |config|
          config.telemetry do |telemetry|
            telemetry.metrics_enabled = false
          end
        end

        example.run
      end

      it 'returns empty string' do
        expect(exporter.export).to eq("")
      end
    end

    context 'when no metrics are available' do
      before do
        allow(backend).to receive(:export).and_return({
          timestamp: '2023-06-23T10:39:42Z',
          total_metrics: 0,
          metrics: {}
        })
      end

      it 'returns empty string' do
        expect(exporter.export).to eq("")
      end
    end

    context 'with counter metrics' do
      before do
        allow(backend).to receive(:export).and_return({
          timestamp: '2023-06-23T10:39:42Z',
          total_metrics: 2,
          metrics: {
            'task_completed_total' => {
              name: 'task_completed_total',
              type: :counter,
              value: 125,
              labels: { status: 'success', handler: 'ProcessOrder' }
            },
            'api_requests_total' => {
              name: 'api_requests_total',
              type: :counter,
              value: 847,
              labels: { endpoint: '/tasks', method: 'POST' }
            }
          }
        })
      end

      it 'exports counters in Prometheus format' do
        result = exporter.export

        expect(result).to include('# Tasker metrics export')
        expect(result).to include('# GENERATED 2023-06-23T10:39:42Z')
        expect(result).to include('# TOTAL_METRICS 2')

        # Counter 1
        expect(result).to include('# HELP task_completed_total Total number of tasks processed')
        expect(result).to include('# TYPE task_completed_total counter')
        expect(result).to include('task_completed_total{status="success",handler="ProcessOrder"} 125')

        # Counter 2
        expect(result).to include('# HELP api_requests_total Tasker counter metric: api_requests_total')
        expect(result).to include('# TYPE api_requests_total counter')
        expect(result).to include('api_requests_total{endpoint="/tasks",method="POST"} 847')
      end

      it 'ends with newline' do
        result = exporter.export
        expect(result).to end_with("\n")
      end
    end

    context 'with gauge metrics' do
      before do
        allow(backend).to receive(:export).and_return({
          timestamp: '2023-06-23T10:39:42Z',
          total_metrics: 1,
          metrics: {
            'active_connections' => {
              name: 'active_connections',
              type: :gauge,
              value: 42,
              labels: { database: 'primary' }
            }
          }
        })
      end

      it 'exports gauges in Prometheus format' do
        result = exporter.export

        expect(result).to include('# HELP active_connections Number of active connections')
        expect(result).to include('# TYPE active_connections gauge')
        expect(result).to include('active_connections{database="primary"} 42')
      end
    end

    context 'with histogram metrics' do
      before do
        allow(backend).to receive(:export).and_return({
          timestamp: '2023-06-23T10:39:42Z',
          total_metrics: 1,
          metrics: {
            'request_duration_seconds' => {
              name: 'request_duration_seconds',
              type: :histogram,
              count: 156,
              sum: 78.3,
              buckets: { 0.1 => 45, 0.5 => 120, 1.0 => 156, 'Inf' => 156 },
              labels: { endpoint: '/tasks' }
            }
          }
        })
      end

      it 'exports histograms in Prometheus format' do
        result = exporter.export

        expect(result).to include('# HELP request_duration_seconds Tasker histogram metric: request_duration_seconds')
        expect(result).to include('# TYPE request_duration_seconds histogram')

        # Buckets
        expect(result).to include('request_duration_seconds_bucket{endpoint="/tasks",le="0.1"} 45')
        expect(result).to include('request_duration_seconds_bucket{endpoint="/tasks",le="0.5"} 120')
        expect(result).to include('request_duration_seconds_bucket{endpoint="/tasks",le="1.0"} 156')
        expect(result).to include('request_duration_seconds_bucket{endpoint="/tasks",le="Inf"} 156')

        # Sum and count
        expect(result).to include('request_duration_seconds_sum{endpoint="/tasks"} 78.3')
        expect(result).to include('request_duration_seconds_count{endpoint="/tasks"} 156')
      end
    end

    context 'with mixed metric types' do
      before do
        allow(backend).to receive(:export).and_return({
          timestamp: '2023-06-23T10:39:42Z',
          total_metrics: 3,
          metrics: {
            'tasks_total' => {
              name: 'tasks_total',
              type: :counter,
              value: 500,
              labels: {}
            },
            'current_queue_size' => {
              name: 'current_queue_size',
              type: :gauge,
              value: 15,
              labels: {}
            },
            'task_duration_seconds' => {
              name: 'task_duration_seconds',
              type: :histogram,
              count: 100,
              sum: 250.0,
              buckets: { 1.0 => 80, 5.0 => 95, 'Inf' => 100 },
              labels: {}
            }
          }
        })
      end

      it 'exports all metric types in correct order' do
        result = exporter.export

        # Should have counters first
        counter_index = result.index('# TYPE tasks_total counter')
        gauge_index = result.index('# TYPE current_queue_size gauge')
        histogram_index = result.index('# TYPE task_duration_seconds histogram')

        expect(counter_index).to be < gauge_index
        expect(gauge_index).to be < histogram_index
      end

      it 'formats metrics without labels correctly' do
        result = exporter.export

        expect(result).to include('tasks_total 500')
        expect(result).to include('current_queue_size 15')
        expect(result).to include('task_duration_seconds_count 100')
      end
    end

    context 'when backend export fails' do
      before do
        allow(backend).to receive(:export).and_raise(StandardError, 'Backend failure')
        allow(Rails).to receive(:logger).and_return(double('Logger', error: nil))
      end

      it 'returns error metric' do
        result = exporter.export

        expect(result).to include('# Export error fallback metric')
        expect(result).to include('# TYPE tasker_metrics_export_errors_total counter')
        expect(result).to include('tasker_metrics_export_errors_total{error="StandardError"} 1')
      end

      it 'logs the error' do
        logger = double('Logger')
        allow(Rails).to receive(:logger).and_return(logger)
        expect(logger).to receive(:error) do |json_string|
          parsed = JSON.parse(json_string)
          expect(parsed["message"]).to eq("Prometheus export failed")
          expect(parsed["error"]).to eq("Backend failure")
          expect(parsed["component"]).to eq("prometheus_exporter")
        end

        exporter.export
      end
    end
  end

  describe '#safe_export' do
    context 'when export succeeds' do
      before do
        allow(backend).to receive(:export).and_return({
          timestamp: '2023-06-23T10:39:42Z',
          total_metrics: 1,
          metrics: {
            'test_metric' => {
              name: 'test_metric',
              type: :counter,
              value: 1,
              labels: {}
            }
          }
        })
                 # Mock metrics count via export
         # (backend.export already returns total_metrics: 1)
      end

      it 'returns success response with data' do
        result = exporter.safe_export

        expect(result[:success]).to be true
        expect(result[:data]).to include('test_metric 1')
        expect(result[:total_metrics]).to eq(1)
        expect(result[:timestamp]).to be_present
      end
    end

    context 'when export fails' do
      before do
        allow(backend).to receive(:export).and_raise(StandardError, 'Export error')
      end

      it 'returns error response' do
        result = exporter.safe_export

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Export error')
        expect(result[:total_metrics]).to eq(0)
        expect(result[:timestamp]).to be_present
      end
    end
  end

  describe 'label escaping' do
    before do
      allow(backend).to receive(:export).and_return({
        timestamp: '2023-06-23T10:39:42Z',
        total_metrics: 1,
        metrics: {
          'test_metric' => {
            name: 'test_metric',
            type: :counter,
            value: 1,
            labels: {
              'label_with_quotes' => 'value "with quotes"',
              'label_with_backslash' => 'value\\with\\backslash'
            }
          }
        }
      })
    end

    it 'properly escapes label values' do
      result = exporter.export

      expect(result).to include('label_with_quotes="value \\"with quotes\\""')
              expect(result).to include('label_with_backslash="value\\with\\backslash"')
    end
  end

  describe 'help text generation' do
    it 'generates appropriate help text for different metric patterns' do
      patterns = [
        ['task_completed_total', :counter, 'Total number of tasks processed'],
        ['step_execution_duration', :histogram, 'Step execution duration in seconds'],
        ['workflow_orchestrations_total', :counter, 'Total number of workflow orchestrations'],
        ['event_published_total', :counter, 'Total number of events published'],
        ['error_count_total', :counter, 'Total number of errors encountered'],
        ['queue_size', :gauge, 'Current queue size'],
        ['active_database_connections', :gauge, 'Number of active connections'],
        ['unknown_metric', :gauge, 'Tasker gauge metric: unknown_metric']
      ]

      patterns.each do |metric_name, type, expected_help|
        help_text = exporter.send(:help_text_for, metric_name, type)
        expect(help_text).to eq(expected_help), "Expected '#{expected_help}' for '#{metric_name}', got '#{help_text}'"
      end
    end
  end
end
