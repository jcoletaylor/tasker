# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Telemetry::MetricsBackend do
  let(:backend) { described_class.instance }
  let(:event_router) { Tasker::Telemetry::EventRouter.instance }

  around do |example|
    # Store original state
    original_metrics = backend.all_metrics.dup
    original_router = backend.event_router

    example.run

    # Restore state
    backend.clear!
    original_metrics.each { |key, metric| backend.instance_variable_get(:@metrics)[key] = metric }
    backend.instance_variable_set(:@event_router, original_router)
  end

  describe '#initialize' do
    it 'is a singleton' do
      expect(described_class.instance).to be(described_class.instance)
    end

    it 'initializes with empty metrics storage' do
      backend.clear!
      expect(backend.metrics).to be_a(Concurrent::Hash)
      expect(backend.all_metrics).to be_empty
    end

    it 'has creation timestamp' do
      expect(backend.created_at).to be_a(Time)
      expect(backend.created_at).to be_frozen
    end

    it 'starts with no event router registered' do
      # Test via the singleton instance after clearing state
      backend.instance_variable_set(:@event_router, nil)
      expect(backend.event_router).to be_nil
    end
  end

  describe '#register_event_router' do
    let(:mock_router) { double('EventRouter') }

    it 'registers an event router' do
      expect { backend.register_event_router(mock_router) }
        .to change { backend.event_router }.to(mock_router)
    end

    it 'returns the registered router' do
      result = backend.register_event_router(mock_router)
      expect(result).to be(mock_router)
    end
  end

  describe '#counter' do
    it 'creates a new counter metric' do
      counter = backend.counter('test_requests_total')
      expect(counter).to be_a(Tasker::Telemetry::MetricTypes::Counter)
      expect(counter.name).to eq('test_requests_total')
      expect(counter.value).to eq(0)
    end

    it 'supports dimensional labels' do
      counter = backend.counter('http_requests_total', endpoint: '/api/v1', method: 'GET')
      expect(counter.labels).to eq({ endpoint: '/api/v1', method: 'GET' })
    end

    it 'returns existing counter for same name and labels' do
      counter1 = backend.counter('existing_counter', env: 'test')
      counter2 = backend.counter('existing_counter', env: 'test')
      expect(counter1).to be(counter2)
    end

    it 'creates separate counters for different labels' do
      counter1 = backend.counter('requests_total', status: '200')
      counter2 = backend.counter('requests_total', status: '404')
      expect(counter1).not_to be(counter2)
      expect(counter1.labels).to eq({ status: '200' })
      expect(counter2.labels).to eq({ status: '404' })
    end

    it 'requires valid metric name' do
      expect { backend.counter(nil) }.to raise_error(ArgumentError, /name cannot be nil or empty/)
      expect { backend.counter('') }.to raise_error(ArgumentError, /name cannot be nil or empty/)
    end

    it 'is thread-safe' do
      threads = []
      counters = []

      10.times do |i|
        threads << Thread.new do
          counters << backend.counter("thread_counter_#{i}")
        end
      end

      threads.each(&:join)
      expect(counters.size).to eq(10)
      expect(counters.map(&:name).uniq.size).to eq(10)
    end
  end

  describe '#gauge' do
    it 'creates a new gauge metric' do
      gauge = backend.gauge('active_connections')
      expect(gauge).to be_a(Tasker::Telemetry::MetricTypes::Gauge)
      expect(gauge.name).to eq('active_connections')
      expect(gauge.value).to eq(0)
    end

    it 'supports dimensional labels' do
      gauge = backend.gauge('memory_usage', process: 'worker', unit: 'bytes')
      expect(gauge.labels).to eq({ process: 'worker', unit: 'bytes' })
    end

    it 'returns existing gauge for same name and labels' do
      gauge1 = backend.gauge('existing_gauge', service: 'api')
      gauge2 = backend.gauge('existing_gauge', service: 'api')
      expect(gauge1).to be(gauge2)
    end

    it 'creates separate gauges for different labels' do
      gauge1 = backend.gauge('cpu_usage', core: '0')
      gauge2 = backend.gauge('cpu_usage', core: '1')
      expect(gauge1).not_to be(gauge2)
    end

    it 'requires valid metric name' do
      expect { backend.gauge(nil) }.to raise_error(ArgumentError, /name cannot be nil or empty/)
    end

    it 'is thread-safe' do
      threads = []
      gauge = backend.gauge('thread_safe_gauge')

      100.times do
        threads << Thread.new do
          gauge.increment(1)
        end
      end

      threads.each(&:join)
      expect(gauge.value).to eq(100)
    end
  end

  describe '#histogram' do
    it 'creates a new histogram metric' do
      histogram = backend.histogram('request_duration_seconds')
      expect(histogram).to be_a(Tasker::Telemetry::MetricTypes::Histogram)
      expect(histogram.name).to eq('request_duration_seconds')
      expect(histogram.count).to eq(0)
    end

    it 'supports custom buckets' do
      custom_buckets = [0.1, 0.5, 1.0, 5.0]
      histogram = backend.histogram('custom_duration', buckets: custom_buckets)
      expect(histogram.bucket_boundaries).to eq(custom_buckets)
    end

    it 'supports dimensional labels' do
      histogram = backend.histogram('task_duration', handler: 'ProcessOrder', status: 'success')
      expect(histogram.labels).to eq({ handler: 'ProcessOrder', status: 'success' })
    end

    it 'returns existing histogram for same name and labels' do
      histogram1 = backend.histogram('existing_histogram', type: 'latency')
      histogram2 = backend.histogram('existing_histogram', type: 'latency')
      expect(histogram1).to be(histogram2)
    end

    it 'creates separate histograms for different buckets' do
      histogram1 = backend.histogram('duration_1', buckets: [0.1, 1.0])
      histogram2 = backend.histogram('duration_2', buckets: [0.5, 2.0])
      expect(histogram1).not_to be(histogram2)
    end

    it 'requires valid metric name' do
      expect { backend.histogram(nil) }.to raise_error(ArgumentError, /name cannot be nil or empty/)
    end

    it 'is thread-safe during creation and observation' do
      threads = []
      histogram = backend.histogram('thread_safe_histogram')
      observations_per_thread = 1000

      5.times do
        threads << Thread.new do
          observations_per_thread.times { |i| histogram.observe(i * 0.001) }
        end
      end

      threads.each(&:join)
      expect(histogram.count).to eq(5 * observations_per_thread)
    end
  end

  describe '#handle_event' do
    before do
      backend.clear!
    end

    context 'with task lifecycle events' do
      it 'handles task.completed events' do
        payload = { task_id: '123', duration: 2.5, status: 'success' }

        result = backend.handle_event('task.completed', payload)
        expect(result).to be(true)

        # Should create completion counter
        counter = backend.all_metrics.values.find { |m| m.name == 'task_completed_total' }
        expect(counter).to be_a(Tasker::Telemetry::MetricTypes::Counter)
        expect(counter.value).to eq(1)

        # Should create duration histogram
        histogram = backend.all_metrics.values.find { |m| m.name == 'task_duration_seconds' }
        expect(histogram).to be_a(Tasker::Telemetry::MetricTypes::Histogram)
        expect(histogram.count).to eq(1)
        expect(histogram.sum).to eq(2.5)
      end

      it 'handles task.failed events' do
        payload = { task_id: '456', duration: 1.2, status: 'error', error: 'timeout' }

        result = backend.handle_event('task.failed', payload)
        expect(result).to be(true)

        # Should create failure counter
        counter = backend.all_metrics.values.find { |m| m.name == 'task_failed_total' }
        expect(counter).to be_a(Tasker::Telemetry::MetricTypes::Counter)
        expect(counter.value).to eq(1)

        # Should record duration even for failures
        histogram = backend.all_metrics.values.find { |m| m.name == 'task_duration_seconds' }
        expect(histogram).to be_a(Tasker::Telemetry::MetricTypes::Histogram)
        expect(histogram.sum).to eq(1.2)
      end

      it 'handles task.started events' do
        payload = { task_id: '789', handler_class: 'ProcessOrder' }

        result = backend.handle_event('task.started', payload)
        expect(result).to be(true)

        counter = backend.all_metrics.values.find { |m| m.name == 'task_started_total' }
        expect(counter).to be_a(Tasker::Telemetry::MetricTypes::Counter)
        expect(counter.value).to eq(1)
        expect(counter.labels).to eq({ 'handler' => 'ProcessOrder' })
      end

      it 'handles task.cancelled events' do
        payload = { task_id: '101', reason: 'user_request' }

        result = backend.handle_event('task.cancelled', payload)
        expect(result).to be(true)

        counter = backend.all_metrics.values.find { |m| m.name == 'task_cancelled_total' }
        expect(counter).to be_a(Tasker::Telemetry::MetricTypes::Counter)
        expect(counter.value).to eq(1)
      end
    end

    context 'with step lifecycle events' do
      it 'handles step.completed events with dimensional labels' do
        payload = {
          step_id: '123',
          task_id: '456',
          duration: 0.5,
          status: 'success',
          handler_class: 'ValidateOrder',
          namespace: 'ecommerce'
        }

        result = backend.handle_event('step.completed', payload)
        expect(result).to be(true)

        counter = backend.all_metrics.values.find { |m| m.name == 'step_completed_total' }
        expect(counter).to be_a(Tasker::Telemetry::MetricTypes::Counter)
        expect(counter.value).to eq(1)
        expect(counter.labels).to eq({
          'status' => 'success',
          'handler' => 'ValidateOrder',
          'namespace' => 'ecommerce'
        })
      end

      it 'handles step.failed events' do
        payload = { step_id: '789', duration: 0.1, status: 'error' }

        result = backend.handle_event('step.failed', payload)
        expect(result).to be(true)

        counter = backend.all_metrics.values.find { |m| m.name == 'step_failed_total' }
        expect(counter.value).to eq(1)
      end
    end

    context 'with workflow orchestration events' do
      it 'handles workflow.iteration events' do
        payload = {
          active_task_count: 42,
          iteration_duration: 0.125,
          batch_size: 10
        }

        result = backend.handle_event('workflow.iteration', payload)
        expect(result).to be(true)

        # Should set active tasks gauge
        gauge = backend.all_metrics.values.find { |m| m.name == 'workflow_active_tasks' }
        expect(gauge).to be_a(Tasker::Telemetry::MetricTypes::Gauge)
        expect(gauge.value).to eq(42)

        # Should record iteration duration
        histogram = backend.all_metrics.values.find { |m| m.name == 'workflow_iteration_duration_seconds' }
        expect(histogram).to be_a(Tasker::Telemetry::MetricTypes::Histogram)
        expect(histogram.sum).to eq(0.125)
      end
    end

    context 'with system health events' do
      it 'handles system.health events' do
        payload = {
          healthy_task_count: 100,
          failed_task_count: 5,
          total_task_count: 105
        }

        result = backend.handle_event('system.health', payload)
        expect(result).to be(true)

        healthy_gauge = backend.all_metrics.values.find { |m| m.name == 'system_healthy_tasks' }
        expect(healthy_gauge.value).to eq(100)

        failed_gauge = backend.all_metrics.values.find { |m| m.name == 'system_failed_tasks' }
        expect(failed_gauge.value).to eq(5)
      end
    end

    context 'error handling' do
      it 'returns false for non-hash payloads' do
        expect(backend.handle_event('task.completed', 'invalid')).to be(false)
        expect(backend.handle_event('task.completed', nil)).to be(false)
        expect(backend.handle_event('task.completed', 123)).to be(false)
      end

      it 'handles unknown event types gracefully' do
        result = backend.handle_event('unknown.event', { data: 'test' })
        expect(result).to be(true)  # No error, just no action taken
      end

      it 'gracefully handles metric creation errors' do
        # Mock a metric creation failure
        allow(Tasker::Telemetry::MetricTypes::Counter).to receive(:new).and_raise(StandardError, 'test error')

        expect { backend.handle_event('task.completed', { duration: 1.0 }) }.not_to raise_error
      end

      it 'warns about errors but does not raise' do
        allow(backend).to receive(:counter).and_raise(StandardError, 'test error')

        expect(backend).to receive(:warn).with(/MetricsBackend failed to handle event/)
        result = backend.handle_event('task.completed', { duration: 1.0 })
        expect(result).to be(false)
      end
    end
  end

  describe '#all_metrics' do
    before do
      backend.clear!
      backend.counter('test_counter').increment
      backend.gauge('test_gauge').set(42)
      backend.histogram('test_histogram').observe(1.5)
    end

    it 'returns a thread-safe snapshot of all metrics' do
      metrics = backend.all_metrics
      expect(metrics).to be_a(Hash)
      expect(metrics.size).to eq(3)

      expect(metrics.values.map(&:class)).to match_array([
        Tasker::Telemetry::MetricTypes::Counter,
        Tasker::Telemetry::MetricTypes::Gauge,
        Tasker::Telemetry::MetricTypes::Histogram
      ])
    end

    it 'returns a snapshot that does not affect the original registry' do
      original_size = backend.metrics.size
      snapshot = backend.all_metrics
      snapshot.clear

      expect(backend.metrics.size).to eq(original_size)
    end
  end

  describe '#export' do
    before do
      backend.clear!
      backend.counter('export_counter').increment(5)
      backend.gauge('export_gauge').set(10.5)
      backend.histogram('export_histogram').observe(2.5)
    end

    it 'exports comprehensive metric data' do
      export = backend.export

      expect(export).to include(
        :timestamp,
        :backend_created_at,
        :total_metrics,
        :metrics
      )

      expect(export[:timestamp]).to be_a(Time)
      expect(export[:backend_created_at]).to eq(backend.created_at)
      expect(export[:total_metrics]).to eq(3)
      expect(export[:metrics]).to be_a(Hash)

      # Check metric data structure
      metric_data = export[:metrics].values.first
      expect(metric_data).to include(:name, :labels, :type, :created_at)
    end

    it 'exports data in monitoring system compatible format' do
      export = backend.export

      export[:metrics].each do |key, metric_data|
        expect(metric_data).to have_key(:name)
        expect(metric_data).to have_key(:type)
        expect(metric_data).to have_key(:created_at)

        case metric_data[:type]
        when :counter
          expect(metric_data).to have_key(:value)
        when :gauge
          expect(metric_data).to have_key(:value)
        when :histogram
          expect(metric_data).to have_key(:count)
          expect(metric_data).to have_key(:sum)
          expect(metric_data).to have_key(:buckets)
        end
      end
    end
  end

  describe '#stats' do
    before do
      backend.clear!
      2.times { |i| backend.counter("counter_#{i}").increment }
      3.times { |i| backend.gauge("gauge_#{i}").set(i) }
      1.times { |i| backend.histogram("histogram_#{i}").observe(i) }
    end

    it 'returns comprehensive backend statistics' do
      stats = backend.stats

      expect(stats).to include(
        total_metrics: 6,
        counter_metrics: 2,
        gauge_metrics: 3,
        histogram_metrics: 1,
        backend_uptime: be_a(Numeric),
        created_at: backend.created_at
      )

      expect(stats[:backend_uptime]).to be > 0
    end

    it 'calculates uptime correctly' do
      stats = backend.stats
      uptime = stats[:backend_uptime]

      sleep 0.001  # Small delay
      later_stats = backend.stats
      later_uptime = later_stats[:backend_uptime]

      expect(later_uptime).to be > uptime
    end
  end

  describe '#clear!' do
    before do
      backend.counter('test_counter').increment
      backend.gauge('test_gauge').set(42)
    end

    it 'clears all metrics and returns count' do
      expect(backend.all_metrics.size).to be > 0

      cleared_count = backend.clear!
      expect(cleared_count).to be > 0
      expect(backend.all_metrics).to be_empty
    end

    it 'is thread-safe' do
      threads = []

      # Add metrics concurrently
      10.times do |i|
        threads << Thread.new do
          backend.counter("concurrent_counter_#{i}").increment
        end
      end

      threads.each(&:join)
      expect(backend.all_metrics.size).to be >= 10

      # Clear should work safely
      expect { backend.clear! }.not_to raise_error
      expect(backend.all_metrics).to be_empty
    end
  end

  describe 'Thread safety' do
    it 'handles concurrent metric creation and updates safely' do
      backend.clear!
      threads = []
      counter_name = 'thread_safety_test'
      iterations = 1000

      # Create multiple threads that increment the same counter
      5.times do
        threads << Thread.new do
          counter = backend.counter(counter_name)
          iterations.times { counter.increment }
        end
      end

      # Create multiple threads that create different counters
      10.times do |i|
        threads << Thread.new do
          backend.counter("unique_counter_#{i}").increment
        end
      end

      threads.each(&:join)

      # Verify the shared counter received all increments
      shared_counter = backend.counter(counter_name)
      expect(shared_counter.value).to eq(5 * iterations)

      # Verify all unique counters were created
      unique_counters = backend.all_metrics.select { |key, _| key.include?('unique_counter') }
      expect(unique_counters.size).to eq(10)
    end
  end

  describe 'Performance characteristics' do
    it 'handles high-volume metric operations efficiently' do
      backend.clear!

            # Test metric creation performance
      expect {
        1000.times { |i| backend.counter("perf_counter_#{i}") }
      }.to take_less_than(0.5)

      # Test metric updates performance
      counter = backend.counter('perf_test_counter')
      expect {
        10_000.times { counter.increment }
      }.to take_less_than(0.1)

      # Test histogram observations performance
      histogram = backend.histogram('perf_test_histogram')
      expect {
        10_000.times { |i| histogram.observe(i * 0.001) }
      }.to take_less_than(1.0)
    end
  end
end

# Reuse the timing matcher from metric_types_spec.rb
RSpec::Matchers.define :take_less_than do |expected_duration|
  supports_block_expectations

  match do |block|
    start_time = Time.current
    block.call
    end_time = Time.current
    @actual_duration = end_time - start_time
    @actual_duration < expected_duration
  end

  failure_message do
    "expected block to take less than #{expected_duration} seconds, but took #{@actual_duration.round(4)} seconds"
  end
end
