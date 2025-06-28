# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Cache Store Integration', type: :cache_store do
  let(:backend) { Tasker::Telemetry::MetricsBackend.instance }

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

  describe 'Rails Cache Store Detection' do
    context 'with different cache store types' do
      CacheStoreHelpers::CACHE_STORES.each_key do |store_type|
        context "with #{store_type}" do
          it 'detects capabilities correctly' do
            # Skip Redis/Memcache tests if gems not available
            if store_type == :redis_store && !defined?(Redis)
              skip 'Redis gem not available for testing'
              next
            end

            if store_type == :memcache_store && !defined?(Dalli)
              skip 'Dalli gem not available for testing'
              next
            end

            expected_capabilities = expected_cache_capabilities(store_type)
            expected_strategy = expected_sync_strategy(store_type)

            with_cache_store(store_type) do
              # Create new backend instance to trigger detection
              test_backend = Tasker::Telemetry::MetricsBackend.send(:new)

              capabilities = test_backend.cache_capabilities
              strategy = test_backend.sync_strategy

              # Verify core capabilities
              expect(capabilities[:distributed]).to eq(expected_capabilities[:distributed])
              expect(capabilities[:atomic_increment]).to eq(expected_capabilities[:atomic_increment])
              expect(capabilities[:locking]).to eq(expected_capabilities[:locking])
              expect(capabilities[:store_class]).to eq(expected_capabilities[:store_class])

              # Verify strategy selection
              expect(strategy).to eq(expected_strategy)

              # Verify Rails-specific capabilities
              expect(capabilities[:key_transformation]).to be true
            end
          end
        end
      end
    end
  end

  describe 'Cache Key Generation' do
    it 'follows Rails caching guide patterns' do
      backend.clear!
      backend.counter('test_metric', service: 'api', env: 'test')

      # Verify structured key generation
      metric_key = backend.send(:build_metric_key, 'test_metric', { service: 'api', env: 'test' })
      cache_key = backend.send(:build_cache_key, metric_key)

      expect(cache_key).to be_an(Array)
      expect(cache_key).to include('tasker', 'metrics')
      expect(cache_key.last).to include('test_metric')
    end

    it 'handles complex key structures as recommended by Rails guide' do
      complex_labels = {
        namespace: 'payments',
        handler: 'ProcessOrder',
        status: 'success',
        version: '1.2.3'
      }

      backend.clear!
      backend.counter('complex_metric', **complex_labels)

      metric_key = backend.send(:build_metric_key, 'complex_metric', complex_labels)
      cache_key = backend.send(:build_cache_key, metric_key)

      # Use memory store for actual caching test since NullStore doesn't persist
      with_cache_store(:memory_store) do
        # Verify Rails can handle the structured key
        expect { Rails.cache.write(cache_key, 'test_value') }.not_to raise_error
        expect(Rails.cache.read(cache_key)).to eq('test_value')
      end
    end
  end

  describe 'Sync Strategy Implementation' do
    before do
      backend.clear!
      backend.counter('sync_test_counter').increment(5)
      backend.gauge('sync_test_gauge').set(10)
      backend.histogram('sync_test_histogram').observe(2.5)
    end

    context 'with local_only strategy (NullStore/MemoryStore)' do
      it 'creates structured cache snapshots' do
        with_cache_store(:memory_store) do
          test_backend = Tasker::Telemetry::MetricsBackend.send(:new)
          test_backend.instance_variable_set(:@metrics, backend.metrics)

          result = test_backend.sync_to_cache!

          expect(result[:success]).to be true
          expect(result[:strategy]).to eq(:local_only)

          # Verify snapshot was created with structured key
          snapshot_key = ['tasker', 'metrics', 'snapshot', test_backend.instance_id]
          snapshot = Rails.cache.read(snapshot_key)

          expect(snapshot).to be_present
          expect(snapshot[:instance_id]).to eq(test_backend.instance_id)
          expect(snapshot[:total_metrics]).to be > 0
        end
      end
    end

    context 'with distributed strategies', :requires_redis do
      it 'uses atomic operations for Redis' do
        skip 'Redis not available' unless defined?(Redis)

        with_cache_store(:redis_store) do
          test_backend = Tasker::Telemetry::MetricsBackend.send(:new)
          test_backend.instance_variable_set(:@metrics, backend.metrics)

          expect(test_backend.sync_strategy).to eq(:distributed_atomic)

          # Mock atomic operations
          allow(Rails.cache).to receive(:increment)
          allow(Rails.cache).to receive(:write)

          result = test_backend.sync_to_cache!

          expect(result[:success]).to be true
          expect(result[:strategy]).to eq(:distributed_atomic)
        end
      end

      it 'uses read-modify-write for basic distributed caches' do
        skip 'Dalli not available' unless defined?(Dalli)

        with_cache_store(:memcache_store) do
          test_backend = Tasker::Telemetry::MetricsBackend.send(:new)
          test_backend.instance_variable_set(:@metrics, backend.metrics)

          expect(test_backend.sync_strategy).to eq(:distributed_basic)

          # Mock read-modify-write operations
          allow(Rails.cache).to receive(:read).and_return(nil)
          allow(Rails.cache).to receive(:write)

          result = test_backend.sync_to_cache!

          expect(result[:success]).to be true
          expect(result[:strategy]).to eq(:distributed_basic)
        end
      end
    end
  end

  describe 'Error Handling and Resilience' do
    it 'handles cache store failures gracefully' do
      # Mock Rails.cache to fail during access
      allow(Rails).to receive(:cache).and_raise(StandardError.new('Cache failure'))

      test_backend = Tasker::Telemetry::MetricsBackend.send(:new)

      # Should fall back to default capabilities
      expect(test_backend.cache_capabilities[:store_class]).to eq('Unknown')
      expect(test_backend.sync_strategy).to eq(:local_only)
    end

    it 'logs cache detection errors appropriately' do
      # Expect structured logging for cache unavailability
      expect(Rails.logger).to receive(:warn).with(/Rails.cache unavailable, using fallback configuration/)

      # Force cache detection error
      allow(Rails.cache).to receive(:class).and_raise(StandardError.new('Detection error'))

      Tasker::Telemetry::MetricsBackend.send(:new)
    end
  end

  describe 'Production Patterns' do
    it 'supports namespace configuration' do
      # Test with namespaced cache store
      namespaced_store = ActiveSupport::Cache::MemoryStore.new(namespace: 'tasker_test')

      allow(Rails).to receive(:cache).and_return(namespaced_store)

      test_backend = Tasker::Telemetry::MetricsBackend.send(:new)
      capabilities = test_backend.cache_capabilities

      expect(capabilities[:namespace_support]).to be true
    end

    it 'handles TTL and expiration correctly' do
      with_cache_store(:memory_store) do
        test_backend = Tasker::Telemetry::MetricsBackend.send(:new)
        test_backend.instance_variable_set(:@metrics, backend.metrics)

        # Verify TTL is set during sync
        expect(Rails.cache).to receive(:write).with(
          anything,
          anything,
          hash_including(expires_in: anything)
        )

        test_backend.sync_to_cache!
      end
    end
  end

  describe 'Export Coordination' do
    it 'provides distributed vs local-only export information' do
      # Test distributed export indication
      with_cache_store(:memory_store) do
        test_backend = Tasker::Telemetry::MetricsBackend.send(:new)
        test_backend.instance_variable_set(:@sync_strategy, :distributed_atomic)

        result = test_backend.export_distributed_metrics

        expect(result[:distributed]).to be true
        expect(result[:sync_strategy]).to eq(:distributed_atomic)
      end

      # Test local-only export warning
      with_cache_store(:memory_store) do
        test_backend = Tasker::Telemetry::MetricsBackend.send(:new)

        result = test_backend.export_distributed_metrics

        expect(result[:distributed]).to be false
        expect(result[:sync_strategy]).to eq(:local_only)
        expect(result[:warning]).to include('local-only')
      end
    end
  end

  describe 'Rails Integration Best Practices' do
    it 'follows Rails cache key transformation patterns' do
      # Use memory store for actual caching test since NullStore doesn't persist
      with_cache_store(:memory_store) do
        # Verify that our keys work with Rails cache transformation
        test_key = ['tasker', 'metrics', 'test-instance', 'complex/metric:name']

        expect { Rails.cache.write(test_key, 'test') }.not_to raise_error
        expect(Rails.cache.read(test_key)).to eq('test')
      end
    end

    it 'respects Rails cache configuration' do
      # Test that our implementation respects Rails cache settings
      original_perform_caching = Rails.application.config.action_controller.perform_caching

      begin
        Rails.application.config.action_controller.perform_caching = false

        # Our cache detection should still work regardless of action_controller caching
        test_backend = Tasker::Telemetry::MetricsBackend.send(:new)
        expect(test_backend.cache_capabilities).to be_present
      ensure
        Rails.application.config.action_controller.perform_caching = original_perform_caching
      end
    end
  end
end
