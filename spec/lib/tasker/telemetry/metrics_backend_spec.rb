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

    # Phase 4.2.2.3.1: Cache Detection System Tests
    it 'detects cache capabilities on initialization' do
      expect(backend.cache_capabilities).to be_a(Hash)
      expect(backend.cache_capabilities).to include(
        :distributed,
        :atomic_increment,
        :locking,
        :ttl_inspection,
        :store_class
      )
    end

    it 'selects appropriate sync strategy based on capabilities' do
      expect(backend.sync_strategy).to be_in(%i[distributed_atomic distributed_basic local_only])
    end

    it 'generates unique instance ID' do
      expect(backend.instance_id).to be_a(String)
      expect(backend.instance_id).to include('-') # hostname-pid format
    end

    it 'configures sync parameters' do
      expect(backend.sync_config).to be_a(Hash)
      expect(backend.sync_config).to include(
        :retention_window,
        :export_safety_margin,
        :sync_interval,
        :export_interval
      )
    end
  end

  describe '#register_event_router' do
    let(:mock_router) { double('EventRouter') }

    it 'registers an event router' do
      expect { backend.register_event_router(mock_router) }
        .to change(backend, :event_router).to(mock_router)
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
        expect(result).to be(true) # No error, just no action taken
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

      expect(metrics.values.map(&:class)).to contain_exactly(Tasker::Telemetry::MetricTypes::Counter,
                                                             Tasker::Telemetry::MetricTypes::Gauge, Tasker::Telemetry::MetricTypes::Histogram)
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

      export[:metrics].each_value do |metric_data|
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
      backend.histogram('histogram_0').observe(0)
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

      sleep 0.001 # Small delay
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
      expect do
        1000.times { |i| backend.counter("perf_counter_#{i}") }
      end.to take_less_than(0.5)

      # Test metric updates performance
      counter = backend.counter('perf_test_counter')
      expect do
        10_000.times { counter.increment }
      end.to take_less_than(0.1)

      # Test histogram observations performance
      histogram = backend.histogram('perf_test_histogram')
      expect do
        10_000.times { |i| histogram.observe(i * 0.001) }
      end.to take_less_than(1.0)
    end
  end

  # Phase 4.2.2.3.1: Cache Detection and Synchronization Tests
  describe 'Cache detection system' do
    describe 'cache capability detection' do
      context 'with Rails.cache available' do
        let(:mock_redis_store) { double('RedisCacheStore') }
        let(:mock_memcache_store) { double('MemCacheStore') }
        let(:mock_memory_store) { double('MemoryStore') }

        before do
          allow(Rails).to receive(:cache).and_return(mock_redis_store)
        end

        it 'detects Redis store capabilities correctly' do
          # Mock all respond_to? calls that rails_cache_available? makes
          allow(mock_redis_store).to receive(:respond_to?).with(:read).and_return(true)
          allow(mock_redis_store).to receive(:respond_to?).with(:write).and_return(true)

          # Mock capability detection methods
          allow(mock_redis_store).to receive(:is_a?).with(ActiveSupport::Cache::RedisCacheStore).and_return(true)
          allow(mock_redis_store).to receive(:is_a?).with(ActiveSupport::Cache::MemCacheStore).and_return(false)
          allow(mock_redis_store).to receive(:respond_to?).with(:increment).and_return(true)
          allow(mock_redis_store).to receive(:respond_to?).with(:with_lock).and_return(true)
          allow(mock_redis_store).to receive(:respond_to?).with(:options).and_return(true)
          allow(mock_redis_store).to receive_messages(options: { namespace: 'test', compress: true },
                                                      class: double(name: 'ActiveSupport::Cache::RedisCacheStore'))

          backend = described_class.send(:new) # Create new instance for testing
          capabilities = backend.send(:detect_cache_capabilities)

          expect(capabilities[:distributed]).to be true
          expect(capabilities[:atomic_increment]).to be true
          expect(capabilities[:locking]).to be true
          expect(capabilities[:ttl_inspection]).to be true
          expect(capabilities[:store_class]).to eq('ActiveSupport::Cache::RedisCacheStore')
        end

        it 'detects Memcached store capabilities correctly' do
          allow(Rails).to receive(:cache).and_return(mock_memcache_store)

          # Mock all respond_to? calls that rails_cache_available? makes
          allow(mock_memcache_store).to receive(:respond_to?).with(:read).and_return(true)
          allow(mock_memcache_store).to receive(:respond_to?).with(:write).and_return(true)

          # Mock capability detection methods
          allow(mock_memcache_store).to receive(:is_a?).with(ActiveSupport::Cache::RedisCacheStore).and_return(false)
          allow(mock_memcache_store).to receive(:is_a?).with(ActiveSupport::Cache::MemCacheStore).and_return(true)
          allow(mock_memcache_store).to receive(:respond_to?).with(:increment).and_return(true)
          allow(mock_memcache_store).to receive(:respond_to?).with(:with_lock).and_return(false)
          allow(mock_memcache_store).to receive(:respond_to?).with(:options).and_return(true)
          allow(mock_memcache_store).to receive_messages(options: { namespace: 'test', compress: true },
                                                         class: double(name: 'ActiveSupport::Cache::MemCacheStore'))

          backend = described_class.send(:new)
          capabilities = backend.send(:detect_cache_capabilities)

          expect(capabilities[:distributed]).to be true
          expect(capabilities[:atomic_increment]).to be true
          expect(capabilities[:locking]).to be false
          expect(capabilities[:ttl_inspection]).to be true
          expect(capabilities[:store_class]).to eq('ActiveSupport::Cache::MemCacheStore')
        end

        it 'detects memory store capabilities correctly' do
          allow(Rails).to receive(:cache).and_return(mock_memory_store)

          # Mock all respond_to? calls that rails_cache_available? makes
          allow(mock_memory_store).to receive(:respond_to?).with(:read).and_return(true)
          allow(mock_memory_store).to receive(:respond_to?).with(:write).and_return(true)

          # Mock capability detection methods
          allow(mock_memory_store).to receive(:respond_to?).with(:increment).and_return(false)
          allow(mock_memory_store).to receive(:respond_to?).with(:with_lock).and_return(false)
          allow(mock_memory_store).to receive(:respond_to?).with(:options).and_return(false)
          allow(mock_memory_store).to receive_messages(is_a?: false,
                                                       class: double(name: 'ActiveSupport::Cache::MemoryStore'))

          backend = described_class.send(:new)
          capabilities = backend.send(:detect_cache_capabilities)

          expect(capabilities[:distributed]).to be false
          expect(capabilities[:atomic_increment]).to be false
          expect(capabilities[:locking]).to be false
          expect(capabilities[:ttl_inspection]).to be false
          expect(capabilities[:store_class]).to eq('ActiveSupport::Cache::MemoryStore')
        end
      end

      context 'without Rails.cache available' do
        it 'returns default capabilities when Rails.cache unavailable' do
          # Mock Rails.cache to not be available
          allow(Rails).to receive(:cache).and_raise(StandardError.new('Cache not available'))

          backend = described_class.send(:new)
          capabilities = backend.send(:detect_cache_capabilities)

          expect(capabilities[:distributed]).to be false
          expect(capabilities[:atomic_increment]).to be false
          expect(capabilities[:locking]).to be false
          expect(capabilities[:ttl_inspection]).to be false
          expect(capabilities[:store_class]).to eq('Unknown')
        end
      end
    end

    describe 'sync strategy selection' do
      it 'selects distributed_atomic for full-featured Redis' do
        backend = described_class.send(:new)
        backend.instance_variable_set(:@cache_capabilities, {
                                        distributed: true,
                                        atomic_increment: true,
                                        locking: true,
                                        ttl_inspection: true
                                      })

        strategy = backend.send(:select_sync_strategy)
        expect(strategy).to eq(:distributed_atomic)
      end

      it 'selects distributed_basic for basic distributed cache' do
        backend = described_class.send(:new)
        backend.instance_variable_set(:@cache_capabilities, {
                                        distributed: true,
                                        atomic_increment: true,
                                        locking: false,
                                        ttl_inspection: true
                                      })

        strategy = backend.send(:select_sync_strategy)
        expect(strategy).to eq(:distributed_basic)
      end

      it 'selects local_only for memory store' do
        backend = described_class.send(:new)
        backend.instance_variable_set(:@cache_capabilities, {
                                        distributed: false,
                                        atomic_increment: false,
                                        locking: false,
                                        ttl_inspection: false
                                      })

        strategy = backend.send(:select_sync_strategy)
        expect(strategy).to eq(:local_only)
      end
    end

    describe 'instance ID generation' do
      it 'generates hostname-pid format' do
        backend = described_class.send(:new)
        instance_id = backend.send(:generate_instance_id)

        expect(instance_id).to match(/\A.+-\d+\z/) # hostname-pid pattern
        expect(instance_id).to include('-')
      end

      it 'handles hostname detection failure gracefully' do
        allow(Socket).to receive(:gethostname).and_raise(StandardError.new('hostname fail'))
        allow(ENV).to receive(:[]).with('HOSTNAME').and_return(nil)

        backend = described_class.send(:new)
        instance_id = backend.send(:generate_instance_id)

        expect(instance_id).to start_with('unknown-')
        expect(instance_id).to end_with(Process.pid.to_s)
      end
    end
  end

  describe 'Cache synchronization' do
    before do
      backend.clear!
      backend.counter('sync_counter').increment(5)
      backend.gauge('sync_gauge').set(10)
      backend.histogram('sync_histogram').observe(2.5)
    end

    describe '#sync_to_cache!' do
      context 'when Rails.cache is unavailable' do
        before do
          allow(backend).to receive(:rails_cache_available?).and_return(false)
        end

        it 'returns failure result' do
          result = backend.sync_to_cache!

          expect(result[:success]).to be false
          expect(result[:error]).to eq('Rails.cache not available')
        end
      end

      context 'with distributed_atomic strategy' do
        before do
          backend.instance_variable_set(:@sync_strategy, :distributed_atomic)
          allow(backend).to receive(:rails_cache_available?).and_return(true)
          allow(Rails.cache).to receive(:increment)
          allow(Rails.cache).to receive(:write)
        end

        it 'syncs using atomic operations' do
          expect(backend).to receive(:sync_with_atomic_operations).and_return({
                                                                                success: true, synced_metrics: 3, strategy: :distributed_atomic
                                                                              })

          result = backend.sync_to_cache!

          expect(result[:success]).to be true
          expect(result[:synced_metrics]).to eq(3)
          expect(result[:strategy]).to eq(:distributed_atomic)
          expect(result[:instance_id]).to eq(backend.instance_id)
        end
      end

      context 'with distributed_basic strategy' do
        before do
          backend.instance_variable_set(:@sync_strategy, :distributed_basic)
          allow(backend).to receive(:rails_cache_available?).and_return(true)
          allow(Rails.cache).to receive(:read)
          allow(Rails.cache).to receive(:write)
        end

        it 'syncs using read-modify-write operations' do
          expect(backend).to receive(:sync_with_read_modify_write).and_return({
                                                                                success: true, synced_metrics: 3, strategy: :distributed_basic
                                                                              })

          result = backend.sync_to_cache!

          expect(result[:success]).to be true
          expect(result[:strategy]).to eq(:distributed_basic)
        end
      end

      context 'with local_only strategy' do
        before do
          backend.instance_variable_set(:@sync_strategy, :local_only)
          allow(backend).to receive(:rails_cache_available?).and_return(true)
          allow(Rails.cache).to receive(:write)
        end

        it 'creates local cache snapshot' do
          expect(backend).to receive(:sync_to_local_cache).and_return({
                                                                        success: true, synced_metrics: 3, strategy: :local_only
                                                                      })

          result = backend.sync_to_cache!

          expect(result[:success]).to be true
          expect(result[:strategy]).to eq(:local_only)
        end
      end

      it 'handles sync errors gracefully' do
        backend.instance_variable_set(:@sync_strategy, :distributed_atomic)
        allow(backend).to receive(:rails_cache_available?).and_return(true)
        allow(backend).to receive(:sync_with_atomic_operations).and_raise(StandardError.new('sync failed'))

        result = backend.sync_to_cache!

        expect(result[:success]).to be false
        expect(result[:error]).to eq('sync failed')
        expect(result[:timestamp]).to be_present
      end
    end

    describe '#export_distributed_metrics' do
      context 'with distributed strategies' do
        before do
          backend.instance_variable_set(:@sync_strategy, :distributed_atomic)
        end

        it 'attempts distributed aggregation' do
          result = backend.export_distributed_metrics

          expect(result[:distributed]).to be true
          expect(result[:sync_strategy]).to eq(:distributed_atomic)
          expect(result[:note]).to include('Phase 4.2.2.3.3')
        end
      end

      context 'with local_only strategy' do
        before do
          backend.instance_variable_set(:@sync_strategy, :local_only)
        end

        it 'exports with warning about local-only mode' do
          result = backend.export_distributed_metrics

          expect(result[:distributed]).to be false
          expect(result[:sync_strategy]).to eq(:local_only)
          expect(result[:warning]).to include('local-only')
        end
      end
    end
  end

  # **Phase 4.2.2.3.2 Adaptive Sync Operations Tests**
  # ===================================================

  describe 'Phase 4.2.2.3.2 Enhanced Sync Operations' do
    before do
      backend.clear!
      # Create test metrics of different types
      backend.counter('test_counter', service: 'api').increment(10)
      backend.counter('another_counter', service: 'worker').increment(5)
      backend.gauge('test_gauge', env: 'prod').set(42.5)
      backend.histogram('test_histogram', operation: 'db_query').observe(1.5)
      backend.histogram('test_histogram', operation: 'db_query').observe(2.5)
    end

    describe '#sync_with_atomic_operations' do
      before do
        backend.instance_variable_set(:@sync_strategy, :distributed_atomic)
        backend.instance_variable_set(:@cache_capabilities, {
                                        distributed: true,
                                        atomic_increment: true,
                                        locking: true,
                                        ttl_inspection: true
                                      })
        allow(Rails.cache).to receive(:increment)
        allow(Rails.cache).to receive(:write)
      end

      it 'returns detailed sync result with performance metrics' do
        result = backend.send(:sync_with_atomic_operations)

        expect(result[:success]).to be true
        expect(result[:strategy]).to eq(:distributed_atomic)
        expect(result[:synced_metrics]).to be > 0
        expect(result[:duration_ms]).to be > 0
        expect(result[:performance]).to be_a(Hash)
        expect(result[:timestamp]).to be_present
      end

      it 'groups metrics by type for batch processing' do
        expect(backend).to receive(:group_metrics_by_type).and_call_original
        expect(backend).to receive(:sync_atomic_counters).and_return({ counters: 2, conflicts: 0 })
        expect(backend).to receive(:sync_distributed_gauges).and_return({ gauges: 1, conflicts: 0 })
        expect(backend).to receive(:sync_distributed_histograms).and_return({ histograms: 1, conflicts: 0 })

        result = backend.send(:sync_with_atomic_operations)
        expect(result[:synced_metrics]).to eq(4) # 2 counters + 1 gauge + 1 histogram
      end

      it 'handles sync errors gracefully with partial results' do
        allow(backend).to receive(:group_metrics_by_type).and_raise(StandardError.new('grouping failed'))

        result = backend.send(:sync_with_atomic_operations)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('grouping failed')
        expect(result[:partial_results]).to be_a(Hash)
        expect(result[:timestamp]).to be_present
      end

      it 'logs successful atomic sync operations' do
        expect(Rails.logger).to receive(:info).with(
          a_string_matching(/Atomic sync completed.*metrics.*conflicts.*batches/)
        )

        backend.send(:sync_with_atomic_operations)
      end
    end

    describe '#sync_with_read_modify_write' do
      before do
        backend.instance_variable_set(:@sync_strategy, :distributed_basic)
        backend.instance_variable_set(:@cache_capabilities, {
                                        distributed: true,
                                        atomic_increment: true,
                                        locking: false,
                                        ttl_inspection: true
                                      })
        allow(Rails.cache).to receive(:read)
        allow(Rails.cache).to receive(:write)
      end

      it 'returns detailed sync result with retry statistics' do
        # Mock the optimistic concurrency method to return successful stats
        allow(backend).to receive(:sync_with_optimistic_concurrency).and_return({
                                                                                  counters: 2, gauges: 1, histograms: 1, retries: 1, conflicts: 0, failed: 0
                                                                                })

        result = backend.send(:sync_with_read_modify_write)

        expect(result[:success]).to be true
        expect(result[:strategy]).to eq(:distributed_basic)
        expect(result[:synced_metrics]).to be > 0
        expect(result[:duration_ms]).to be > 0
        expect(result[:performance]).to include(:retries, :conflicts, :failed)
        expect(result[:timestamp]).to be_present
      end

      it 'uses optimistic concurrency control' do
        expect(backend).to receive(:sync_with_optimistic_concurrency).and_return({
                                                                                   counters: 2, gauges: 1, histograms: 1, retries: 1, conflicts: 0, failed: 0
                                                                                 })

        result = backend.send(:sync_with_read_modify_write)
        expect(result[:performance][:retries]).to eq(1)
      end

      it 'logs successful read-modify-write operations' do
        expect(Rails.logger).to receive(:info).with(
          a_string_matching(/Read-modify-write sync completed.*retries.*failed/)
        )

        backend.send(:sync_with_read_modify_write)
      end
    end

    describe '#sync_to_local_cache' do
      before do
        backend.instance_variable_set(:@sync_strategy, :local_only)
        allow(Rails.cache).to receive(:write).and_return(true)
      end

      it 'returns detailed sync result with snapshot information' do
        result = backend.send(:sync_to_local_cache)

        expect(result[:success]).to be true
        expect(result[:strategy]).to eq(:local_only)
        expect(result[:synced_metrics]).to be > 0
        expect(result[:duration_ms]).to be > 0
        expect(result[:performance]).to include(:snapshots, :metrics_serialized, :size_bytes)
        expect(result[:snapshot_key]).to be_present
        expect(result[:timestamp]).to be_present
      end

      it 'creates versioned snapshots with metadata' do
        expect(backend).to receive(:create_versioned_snapshot).and_call_original

        result = backend.send(:sync_to_local_cache)
        expect(result[:success]).to be true
      end

      it 'handles snapshot creation failures gracefully' do
        allow(Rails.cache).to receive(:write).and_return(false)

        result = backend.send(:sync_to_local_cache)
        expect(result[:success]).to be false
      end

      it 'logs successful local sync operations' do
        expect(Rails.logger).to receive(:info).with(
          a_string_matching(/Local snapshot sync completed.*snapshots.*bytes/)
        )

        backend.send(:sync_to_local_cache)
      end

      it 'creates timestamped snapshots for history when possible' do
        expect(Rails.cache).to receive(:write).twice # Primary + timestamped
        backend.send(:sync_to_local_cache)
      end
    end

    describe 'Supporting methods' do
      describe '#group_metrics_by_type' do
        it 'groups metrics by counter, gauge, histogram types' do
          grouped = backend.send(:group_metrics_by_type)

          expect(grouped[:counter].size).to eq(2)  # test_counter, another_counter
          expect(grouped[:gauge].size).to eq(1)    # test_gauge
          expect(grouped[:histogram].size).to eq(1) # test_histogram
        end

        it 'returns arrays of [key, metric_data] pairs' do
          grouped = backend.send(:group_metrics_by_type)

          key, metric_data = grouped[:counter].first
          expect(key).to be_a(String)
          expect(metric_data).to include(:type, :value, :labels)
          expect(metric_data[:type]).to eq(:counter)
        end
      end

      describe '#sync_atomic_counters' do
        it 'uses atomic increment operations for counters' do
          counters = backend.send(:group_metrics_by_type)[:counter]

          expect(Rails.cache).to receive(:increment).twice # for each counter

          stats = backend.send(:sync_atomic_counters, counters)
          expect(stats[:counters]).to eq(2)
          expect(stats[:conflicts]).to eq(0)
        end

        it 'handles atomic operation failures with fallback' do
          counters = backend.send(:group_metrics_by_type)[:counter]

          allow(Rails.cache).to receive(:increment).and_raise(StandardError.new('atomic failed'))
          expect(Rails.cache).to receive(:write).twice # fallback for each counter

          stats = backend.send(:sync_atomic_counters, counters)
          expect(stats[:conflicts]).to eq(2)  # Both operations failed and fell back
        end
      end

      describe '#sync_distributed_gauges' do
        it 'adds timestamp and instance ID for conflict resolution' do
          gauges = backend.send(:group_metrics_by_type)[:gauge]

          expect(Rails.cache).to receive(:write) do |_key, data, _options|
            expect(data).to include(:last_update, :instance_id)
            expect(data[:last_update]).to be > 0
            expect(data[:instance_id]).to eq(backend.instance_id)
          end

          backend.send(:sync_distributed_gauges, gauges)
        end
      end

      describe '#sync_distributed_histograms' do
        before do
          backend.instance_variable_set(:@cache_capabilities, {
                                          distributed: true,
                                          atomic_increment: true
                                        })
        end

        it 'attempts atomic histogram updates first' do
          histograms = backend.send(:group_metrics_by_type)[:histogram]

          expect(backend).to receive(:attempt_atomic_histogram_update).and_return(true)

          stats = backend.send(:sync_distributed_histograms, histograms)
          expect(stats[:histograms]).to eq(1)
          expect(stats[:conflicts]).to eq(0)
        end

        it 'falls back to merge strategy when atomic operations fail' do
          histograms = backend.send(:group_metrics_by_type)[:histogram]

          expect(backend).to receive(:attempt_atomic_histogram_update).and_return(false)
          expect(Rails.cache).to receive(:read)
          expect(Rails.cache).to receive(:write)

          stats = backend.send(:sync_distributed_histograms, histograms)
          expect(stats[:conflicts]).to eq(1)  # Fallback was used
        end
      end

      describe '#sync_with_optimistic_concurrency' do
        it 'implements retry logic with exponential backoff' do
          grouped_metrics = { counter: [[backend.send(:build_metric_key, 'test', {}), { type: :counter, value: 1 }]] }

          # Simulate write failures that trigger retries
          call_count = 0
          allow(Rails.cache).to receive(:write) do
            call_count += 1
            call_count > 2 # Fail twice, succeed on third try
          end
          allow(Rails.cache).to receive(:read).and_return(nil) # Start with empty cache

          allow(backend).to receive(:sleep) # Don't actually sleep in tests

          stats = backend.send(:sync_with_optimistic_concurrency, grouped_metrics)
          expect(stats[:retries]).to eq(2) # Two retries before success (matches actual implementation)
          expect(stats[:counters]).to eq(1) # Eventually succeeded (note: plural form)
        end

        it 'gives up after maximum retries and marks as failed' do
          grouped_metrics = { counter: [[backend.send(:build_metric_key, 'test', {}),
                                         { type: :counter, value: 1 }]] }

          allow(Rails.cache).to receive(:write).and_return(false) # Always fail
          allow(backend).to receive(:sleep)

          stats = backend.send(:sync_with_optimistic_concurrency, grouped_metrics)
          expect(stats[:failed]).to eq(1)
          expect(stats[:retries]).to eq(3) # Maximum retries attempted
        end
      end

      describe '#create_versioned_snapshot' do
        it 'creates comprehensive snapshot with metadata' do
          snapshot = backend.send(:create_versioned_snapshot)

          expect(snapshot[:version]).to eq(Tasker::VERSION)
          expect(snapshot[:timestamp]).to be_present
          expect(snapshot[:instance_id]).to eq(backend.instance_id)
          expect(snapshot[:cache_strategy]).to be_present
          expect(snapshot[:cache_capabilities]).to be_a(Hash)
          expect(snapshot[:total_metrics]).to be > 0
          expect(snapshot[:metrics_by_type]).to include(:counter, :gauge, :histogram)
          expect(snapshot[:metrics]).to be_a(Hash)
          expect(snapshot[:sync_config]).to be_a(Hash)
          expect(snapshot[:hostname]).to be_present
        end

        it 'includes metrics breakdown by type' do
          snapshot = backend.send(:create_versioned_snapshot)

          expect(snapshot[:metrics_by_type][:counter]).to eq(2)  # test_counter, another_counter
          expect(snapshot[:metrics_by_type][:gauge]).to eq(1)    # test_gauge
          expect(snapshot[:metrics_by_type][:histogram]).to eq(1) # test_histogram
        end
      end

      describe '#estimate_snapshot_size' do
        it 'estimates size in bytes' do
          snapshot_data = { test: 'data', metrics: { counter: 1 } }

          size = backend.send(:estimate_snapshot_size, snapshot_data)
          expect(size).to be > 0
          expect(size).to be_a(Integer)
        end

        it 'handles estimation errors gracefully' do
          allow_any_instance_of(Hash).to receive(:to_json).and_raise(StandardError.new('json error'))

          size = backend.send(:estimate_snapshot_size, { test: 'data' })
          expect(size).to eq(0)
        end
      end
    end

    describe 'Performance characteristics' do
      it 'completes atomic sync operations quickly' do
        backend.instance_variable_set(:@sync_strategy, :distributed_atomic)
        backend.instance_variable_set(:@cache_capabilities, { atomic_increment: true })
        allow(Rails.cache).to receive(:increment)
        allow(Rails.cache).to receive(:write)

        # Should complete in under 100ms
        expect do
          backend.send(:sync_with_atomic_operations)
        end.to take_less_than(0.1)
      end

      it 'includes accurate timing in sync results' do
        result = backend.send(:sync_with_atomic_operations)

        expect(result[:duration_ms]).to be > 0
        expect(result[:duration_ms]).to be < 1000 # Should be well under 1 second
      end
    end

    describe 'Error resilience' do
      it 'isolates failures between metric types' do
        allow(backend).to receive(:sync_atomic_counters).and_raise(StandardError.new('counter sync failed'))
        allow(backend).to receive_messages(sync_distributed_gauges: { gauges: 1, conflicts: 0 },
                                           sync_distributed_histograms: {
                                             histograms: 1, conflicts: 0
                                           })

        result = backend.send(:sync_with_atomic_operations)

        # Should capture partial results even when some operations fail
        expect(result[:success]).to be false
        expect(result[:partial_results]).to be_a(Hash)
      end

      it 'provides detailed error information' do
        allow(backend).to receive(:group_metrics_by_type).and_raise(StandardError.new('critical failure'))

        result = backend.send(:sync_with_atomic_operations)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('critical failure')
        expect(result[:timestamp]).to be_present
      end
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
