# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Telemetry::IntelligentCacheManager do
  let(:cache_config) do
    Tasker::Types::CacheConfig.new(
      default_ttl: 300,
      adaptive_ttl_enabled: true,
      performance_tracking_enabled: true,
      hit_rate_smoothing_factor: 0.9,
      access_frequency_decay_rate: 0.95,
      min_adaptive_ttl: 30,
      max_adaptive_ttl: 1800
    )
  end

  let(:manager) { described_class.new(cache_config) }
  let(:cache_key) { 'test_key' }
  let(:test_value) { 'test_value' }

  before do
    # Mock Rails.cache
    allow(Rails).to receive(:cache).and_return(double('cache'))
    allow(Rails.cache).to receive(:fetch)
    allow(Rails.cache).to receive(:read)
    allow(Rails.cache).to receive(:write)
    allow(Rails.cache).to receive(:delete)

    # Mock cache store class for capability detection
    cache_store = double('cache_store', class: double(name: 'ActiveSupport::Cache::MemoryStore'))
    allow(Rails.cache).to receive(:class).and_return(cache_store.class)
    allow(Rails.cache).to receive(:respond_to?).with(:read).and_return(true)
    allow(Rails.cache).to receive(:respond_to?).with(:write).and_return(true)
    allow(Rails.cache).to receive(:respond_to?).with(:increment).and_return(false)
    allow(Rails.cache).to receive(:respond_to?).with(:decrement).and_return(false)
    allow(Rails.cache).to receive(:respond_to?).with(:options).and_return(false)
  end

  describe '#initialize' do
    it 'initializes with cache configuration' do
      expect(manager.config).to eq(cache_config)
    end

    it 'generates instance ID with hostname-pid pattern' do
      expect(manager.instance_id).to be_a(String)
      expect(manager.instance_id).to match(/\A.+-\d+\z/)
    end

    it 'detects cache capabilities' do
      expect(manager.cache_capabilities).to be_a(Hash)
      expect(manager.cache_capabilities).to include(
        :distributed,
        :atomic_increment,
        :locking,
        :ttl_inspection,
        :store_class
      )
    end

    it 'selects coordination strategy based on capabilities' do
      expect(manager.coordination_strategy).to be_in(%i[distributed_atomic distributed_basic local_only])
    end

    it 'uses global configuration when none provided' do
      telemetry_config_mock = double('telemetry_config',
        parameter_filter: nil,
        log_format: 'json',
        log_level: 'info'
      )
      mock_config = double('config', cache: cache_config, telemetry: telemetry_config_mock)
      allow(Tasker).to receive(:configuration).and_return(mock_config)

      manager = described_class.new

      expect(manager.config).to eq(cache_config)
    end

    it 'logs initialization with structured logging' do
      # Set up expectation on the class before creating the instance
      # The initialization will call multiple log_structured methods, so we need to be more flexible
      expect_any_instance_of(described_class).to receive(:log_structured).at_least(:once)

      described_class.new(cache_config)
    end
  end

  describe '#intelligent_fetch' do
    context 'with local_only coordination strategy' do
      before do
        # Force local_only strategy for predictable testing
        allow(manager).to receive(:coordination_strategy).and_return(:local_only)
      end

      it 'fetches data using local tracking' do
        # Mock the main cache fetch call to yield and return the test value
        expect(Rails.cache).to receive(:fetch).with(cache_key, expires_in: kind_of(Integer)).and_yield.and_return(test_value)

        # Allow performance metrics update
        allow(manager).to receive(:update_local_performance_metrics)

        result = manager.intelligent_fetch(cache_key) { test_value }

        expect(result).to eq(test_value)
      end

      it 'uses adaptive TTL calculation' do
        # Mock performance data fetch
        allow(manager).to receive(:fetch_local_performance_data).and_return({
          hit_rate: 0.8,
          generation_time: 0.5,
          access_frequency: 50
        })

        # Expect adaptive TTL to be used - the actual value will be calculated by CacheConfig
        expect(Rails.cache).to receive(:fetch).with(cache_key, expires_in: kind_of(Integer)).and_yield.and_return(test_value)
        allow(manager).to receive(:update_local_performance_metrics)

        result = manager.intelligent_fetch(cache_key) { test_value }
        expect(result).to eq(test_value)
      end

      it 'handles cache hits correctly' do
        # Mock cache hit (no yield) - Rails.cache.fetch returns value without calling block
        expect(Rails.cache).to receive(:fetch).with(cache_key, expires_in: kind_of(Integer)).and_return(test_value)

        # Should track as hit (cache_miss = false)
        expect(manager).to receive(:update_local_performance_metrics).with(
          cache_key,
          true, # cache hit
          kind_of(Float) # duration
        )

        result = manager.intelligent_fetch(cache_key) { test_value }
        expect(result).to eq(test_value)
      end

      it 'handles cache misses correctly' do
        # Mock cache miss (yields) - Rails.cache.fetch calls the block
        expect(Rails.cache).to receive(:fetch).with(cache_key, expires_in: kind_of(Integer)).and_yield.and_return(test_value)

        # Should track as miss (cache_miss = true)
        expect(manager).to receive(:update_local_performance_metrics).with(
          cache_key,
          false, # cache miss
          kind_of(Float) # duration
        )

        result = manager.intelligent_fetch(cache_key) { test_value }
        expect(result).to eq(test_value)
      end
    end

    context 'with distributed_atomic coordination strategy' do
      let(:manager_with_redis) do
        # Create a fresh manager with Redis-like capabilities
        redis_store = double('redis_store', class: double(name: 'ActiveSupport::Cache::RedisCacheStore'))
        allow(Rails.cache).to receive(:class).and_return(redis_store.class)
        allow(Rails.cache).to receive(:respond_to?).with(:increment).and_return(true)
        allow(Rails.cache).to receive(:respond_to?).with(:decrement).and_return(true)

        described_class.new(cache_config)
      end

      it 'uses atomic coordination for performance tracking' do
        expect(manager_with_redis).to receive(:fetch_atomic_performance_data).and_return({
          hit_rate: 0.0,
          generation_time: 0.0,
          access_frequency: 0
        })

        expect(Rails.cache).to receive(:fetch).with(cache_key, expires_in: kind_of(Integer)).and_yield.and_return(test_value)

        expect(manager_with_redis).to receive(:update_atomic_performance_metrics).with(
          cache_key,
          false,
          kind_of(Float)
        )

        result = manager_with_redis.intelligent_fetch(cache_key) { test_value }
        expect(result).to eq(test_value)
      end
    end

    context 'with distributed_basic coordination strategy' do
      let(:manager_with_memcached) do
        # Create a fresh manager with Memcached-like capabilities
        memcached_store = double('memcached_store', class: double(name: 'ActiveSupport::Cache::MemCacheStore'))
        allow(Rails.cache).to receive(:class).and_return(memcached_store.class)
        allow(Rails.cache).to receive(:respond_to?).with(:increment).and_return(true)
        allow(Rails.cache).to receive(:respond_to?).with(:decrement).and_return(true)

        described_class.new(cache_config)
      end

      it 'uses basic coordination for performance tracking' do
        expect(manager_with_memcached).to receive(:fetch_basic_performance_data).and_return({
          hit_rate: 0.0,
          generation_time: 0.0,
          access_frequency: 0
        })

        expect(Rails.cache).to receive(:fetch).with(cache_key, expires_in: kind_of(Integer)).and_yield.and_return(test_value)

        expect(manager_with_memcached).to receive(:update_basic_performance_metrics).with(
          cache_key,
          false,
          kind_of(Float)
        )

        result = manager_with_memcached.intelligent_fetch(cache_key) { test_value }
        expect(result).to eq(test_value)
      end
    end
  end

  describe '#clear_performance_data' do
    it 'clears performance data for a cache key' do
      performance_key = "#{described_class::CACHE_PERFORMANCE_KEY_PREFIX}:#{manager.instance_id}:#{cache_key}"

      expect(Rails.cache).to receive(:delete).with(performance_key)

      result = manager.clear_performance_data(cache_key)
      expect(result).to be true
    end

    it 'handles errors gracefully' do
      allow(Rails.cache).to receive(:delete).and_raise(StandardError.new("Cache error"))

      result = manager.clear_performance_data(cache_key)
      expect(result).to be false
    end
  end

  describe '#export_performance_metrics' do
    it 'exports metrics based on coordination strategy' do
      result = manager.export_performance_metrics

      expect(result).to be_a(Hash)
      expect(result).to include(:strategy, :instance_id, :cache_store)
    end

    context 'with local_only strategy' do
      before do
        allow(manager).to receive(:coordination_strategy).and_return(:local_only)
      end

      it 'includes warning about local-only metrics' do
        result = manager.export_performance_metrics

        expect(result[:warning]).to include('Local-only metrics')
      end
    end
  end

  describe 'coordination strategy selection' do
    context 'with Redis store' do
      before do
        redis_store = double('redis_store', class: double(name: 'ActiveSupport::Cache::RedisCacheStore'))
        allow(Rails.cache).to receive(:class).and_return(redis_store.class)
        allow(Rails.cache).to receive(:respond_to?).with(:increment).and_return(true)
        allow(Rails.cache).to receive(:respond_to?).with(:decrement).and_return(true)
      end

      it 'selects distributed_atomic strategy' do
        manager = described_class.new(cache_config)
        expect(manager.coordination_strategy).to eq(:distributed_atomic)
      end
    end

    context 'with Memcached store' do
      before do
        memcached_store = double('memcached_store', class: double(name: 'ActiveSupport::Cache::MemCacheStore'))
        allow(Rails.cache).to receive(:class).and_return(memcached_store.class)
        allow(Rails.cache).to receive(:respond_to?).with(:increment).and_return(true)
        allow(Rails.cache).to receive(:respond_to?).with(:decrement).and_return(true)
      end

      it 'selects distributed_basic strategy' do
        manager = described_class.new(cache_config)
        expect(manager.coordination_strategy).to eq(:distributed_basic)
      end
    end

    context 'with Memory store' do
      before do
        memory_store = double('memory_store', class: double(name: 'ActiveSupport::Cache::MemoryStore'))
        allow(Rails.cache).to receive(:class).and_return(memory_store.class)
        allow(Rails.cache).to receive(:respond_to?).with(:increment).and_return(false)
        allow(Rails.cache).to receive(:respond_to?).with(:decrement).and_return(false)
      end

      it 'selects local_only strategy' do
        manager = described_class.new(cache_config)
        expect(manager.coordination_strategy).to eq(:local_only)
      end
    end
  end

  describe 'performance key building' do
    context 'with distributed strategies' do
      let(:manager_with_redis) do
        # Create a fresh manager with Redis-like capabilities for true distributed strategy
        redis_store = double('redis_store', class: double(name: 'ActiveSupport::Cache::RedisCacheStore'))
        allow(Rails.cache).to receive(:class).and_return(redis_store.class)
        allow(Rails.cache).to receive(:respond_to?).with(:increment).and_return(true)
        allow(Rails.cache).to receive(:respond_to?).with(:decrement).and_return(true)

        described_class.new(cache_config)
      end

      it 'builds global performance keys' do
        key = manager_with_redis.send(:build_performance_key, cache_key)
        expect(key).to eq("#{described_class::CACHE_PERFORMANCE_KEY_PREFIX}:#{cache_key}")
      end
    end

    context 'with local_only strategy' do
      # Use the default manager which will be local_only with MemoryStore
      it 'builds instance-specific performance keys' do
        key = manager.send(:build_performance_key, cache_key)
        expect(key).to eq("#{described_class::CACHE_PERFORMANCE_KEY_PREFIX}:#{manager.instance_id}:#{cache_key}")
      end
    end
  end

  describe 'error handling' do
    it 'handles cache errors gracefully' do
      allow(Rails.cache).to receive(:fetch).and_raise(StandardError.new("Cache connection failed"))

      expect { manager.intelligent_fetch(cache_key) { test_value } }.to raise_error(StandardError, "Cache connection failed")
    end

    it 'handles performance data fetch errors' do
      allow(Rails.cache).to receive(:read).and_raise(StandardError.new("Read failed"))
      allow(Rails.cache).to receive(:fetch).with(cache_key, expires_in: kind_of(Integer)).and_yield.and_return(test_value)
      allow(manager).to receive(:update_local_performance_metrics)

      # Should fall back to default performance data
      result = manager.intelligent_fetch(cache_key) { test_value }
      expect(result).to eq(test_value)
    end
  end
end
