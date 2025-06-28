# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::CacheStrategy do
  let(:mock_store) { double('CacheStore') }
  let(:memory_store) { ActiveSupport::Cache::MemoryStore.new }
  let(:redis_store) { double('RedisCacheStore', class: double(name: 'ActiveSupport::Cache::RedisCacheStore')) }
  let(:memcache_store) { double('MemCacheStore', class: double(name: 'ActiveSupport::Cache::MemCacheStore')) }
  let(:solid_cache_store) { double('SolidCacheStore', class: double(name: 'SolidCache::Store')) }
  let(:file_store) { ActiveSupport::Cache::FileStore.new('/tmp/cache') }
  let(:null_store) { ActiveSupport::Cache::NullStore.new }

  before do
    # Clear any registered detectors before each test
    described_class.clear_detectors!

    # Clear strategy cache to prevent interference between tests
    registry = Tasker::DetectorRegistry.instance
    registry.instance_variable_set(:@strategy_cache, {})

    # Mock Rails.cache availability
    allow(Rails).to receive(:cache).and_return(mock_store)
    allow(mock_store).to receive(:respond_to?).with(:read).and_return(true)
    allow(mock_store).to receive(:respond_to?).with(:write).and_return(true)
  end

  describe '.detect' do
    it 'creates a strategy instance for Rails.cache' do
      allow(mock_store).to receive(:class).and_return(double(name: 'ActiveSupport::Cache::MemoryStore'))
      allow(mock_store).to receive(:respond_to?).with(:increment).and_return(false)
      allow(mock_store).to receive(:respond_to?).with(:with_lock).and_return(false)
      allow(mock_store).to receive(:respond_to?).with(:options).and_return(false)

      strategy = described_class.detect
      expect(strategy).to be_a(described_class)
      expect(strategy.store_class_name).to eq('ActiveSupport::Cache::MemoryStore')
    end
  end

  describe 'cache store detection' do
    context 'with Redis cache store' do
      let(:redis_store) { double('RedisCacheStore', class: double(name: 'ActiveSupport::Cache::RedisCacheStore')) }

      before do
        allow(redis_store).to receive(:respond_to?).with(:read).and_return(true)
        allow(redis_store).to receive(:respond_to?).with(:write).and_return(true)
        allow(redis_store).to receive(:respond_to?).with(:increment).and_return(true)
        allow(redis_store).to receive(:respond_to?).with(:with_lock).and_return(true)
        allow(redis_store).to receive(:respond_to?).with(:options).and_return(true)
        allow(redis_store).to receive(:options).and_return({ namespace: 'test', compress: true })
      end

      it 'detects Redis capabilities correctly' do
        allow(Rails).to receive(:cache).and_return(redis_store)
        strategy = described_class.new

        expect(strategy.supports?(:distributed)).to be true
        expect(strategy.supports?(:atomic_increment)).to be true
        expect(strategy.supports?(:locking)).to be true
        expect(strategy.supports?(:ttl_inspection)).to be true
        expect(strategy.supports?(:namespace_support)).to be true
        expect(strategy.supports?(:compression_support)).to be true
        expect(strategy.coordination_mode).to eq(:distributed_atomic)
      end
    end

    context 'with Memcached cache store' do
      let(:memcache_store) { double('MemCacheStore', class: double(name: 'ActiveSupport::Cache::MemCacheStore')) }

      before do
        allow(memcache_store).to receive(:respond_to?).with(:read).and_return(true)
        allow(memcache_store).to receive(:respond_to?).with(:write).and_return(true)
        allow(memcache_store).to receive(:respond_to?).with(:increment).and_return(true)
        allow(memcache_store).to receive(:respond_to?).with(:with_lock).and_return(false)
        allow(memcache_store).to receive(:respond_to?).with(:options).and_return(true)
        allow(memcache_store).to receive(:options).and_return({ namespace: 'test' })
      end

      it 'detects Memcached capabilities correctly' do
        allow(Rails).to receive(:cache).and_return(memcache_store)
        strategy = described_class.new

        expect(strategy.supports?(:distributed)).to be true
        expect(strategy.supports?(:atomic_increment)).to be true
        expect(strategy.supports?(:locking)).to be false
        expect(strategy.supports?(:ttl_inspection)).to be true
        expect(strategy.supports?(:namespace_support)).to be true
        expect(strategy.supports?(:compression_support)).to be false
        expect(strategy.coordination_mode).to eq(:distributed_basic)
      end
    end

    context 'with Solid Cache store' do
      let(:solid_cache_store) { double('SolidCacheStore', class: double(name: 'SolidCache::Store')) }

      before do
        allow(solid_cache_store).to receive(:respond_to?).with(:read).and_return(true)
        allow(solid_cache_store).to receive(:respond_to?).with(:write).and_return(true)
        allow(solid_cache_store).to receive(:respond_to?).with(:increment).and_return(true)
        allow(solid_cache_store).to receive(:respond_to?).with(:with_lock).and_return(true)
        allow(solid_cache_store).to receive(:respond_to?).with(:options).and_return(false)
      end

      it 'detects Solid Cache capabilities correctly' do
        allow(Rails).to receive(:cache).and_return(solid_cache_store)
        strategy = described_class.new

        expect(strategy.supports?(:distributed)).to be true
        expect(strategy.supports?(:atomic_increment)).to be true
        expect(strategy.supports?(:locking)).to be true
        expect(strategy.supports?(:ttl_inspection)).to be true
        expect(strategy.supports?(:namespace_support)).to be false
        expect(strategy.supports?(:compression_support)).to be false
        expect(strategy.coordination_mode).to eq(:distributed_atomic)
      end
    end

    context 'with Memory cache store' do
      let(:memory_store) { double('MemoryStore', class: double(name: 'ActiveSupport::Cache::MemoryStore')) }

      before do
        allow(memory_store).to receive(:respond_to?).with(:read).and_return(true)
        allow(memory_store).to receive(:respond_to?).with(:write).and_return(true)
        allow(memory_store).to receive(:respond_to?).with(:increment).and_return(false)
        allow(memory_store).to receive(:respond_to?).with(:with_lock).and_return(false)
        allow(memory_store).to receive(:respond_to?).with(:options).and_return(false)
      end

      it 'detects Memory store capabilities correctly' do
        allow(Rails).to receive(:cache).and_return(memory_store)
        strategy = described_class.new

        expect(strategy.supports?(:distributed)).to be false
        expect(strategy.supports?(:atomic_increment)).to be false
        expect(strategy.supports?(:locking)).to be false
        expect(strategy.supports?(:ttl_inspection)).to be false
        expect(strategy.supports?(:namespace_support)).to be false
        expect(strategy.supports?(:compression_support)).to be false
        expect(strategy.coordination_mode).to eq(:local_only)
      end
    end
  end

  describe 'custom detector registration' do
    it 'allows registering custom detectors' do
      custom_detector = ->(store) { { distributed: true, atomic_increment: true, locking: true, custom_feature: true } }

      described_class.register_detector(/MyCompany::CustomCacheStore/, custom_detector)

      custom_store = double('CustomStore', class: double(name: 'MyCompany::CustomCacheStore'))
      allow(custom_store).to receive(:respond_to?).with(:read).and_return(true)
      allow(custom_store).to receive(:respond_to?).with(:write).and_return(true)
      allow(custom_store).to receive(:respond_to?).with(:increment).and_return(true)
      allow(custom_store).to receive(:respond_to?).with(:with_lock).and_return(true)
      allow(custom_store).to receive(:respond_to?).with(:options).and_return(false)

      allow(Rails).to receive(:cache).and_return(custom_store)
      strategy = described_class.new

      expect(strategy.supports?(:distributed)).to be true
      expect(strategy.supports?(:atomic_increment)).to be true
      expect(strategy.supports?(:custom_feature)).to be true
      expect(strategy.coordination_mode).to eq(:distributed_atomic)
    end

    it 'supports string pattern matching' do
      custom_detector = ->(store) { { distributed: false, atomic_increment: true } }

      described_class.register_detector('WeirdCacheStore', custom_detector)

      weird_store = double('WeirdStore', class: double(name: 'SomeGem::WeirdCacheStore'))
      allow(weird_store).to receive(:respond_to?).with(:read).and_return(true)
      allow(weird_store).to receive(:respond_to?).with(:write).and_return(true)
      allow(weird_store).to receive(:respond_to?).with(:increment).and_return(true)
      allow(weird_store).to receive(:respond_to?).with(:with_lock).and_return(false)
      allow(weird_store).to receive(:respond_to?).with(:options).and_return(false)

      allow(Rails).to receive(:cache).and_return(weird_store)
      strategy = described_class.new

      expect(strategy.supports?(:distributed)).to be false
      expect(strategy.supports?(:atomic_increment)).to be true
      expect(strategy.coordination_mode).to eq(:local_only)
    end
  end

  describe 'coordination strategy selection' do
    it 'selects distributed_atomic for full-featured stores' do
      redis_store = double('RedisCacheStore', class: double(name: 'ActiveSupport::Cache::RedisCacheStore'))
      allow(redis_store).to receive(:respond_to?).with(:read).and_return(true)
      allow(redis_store).to receive(:respond_to?).with(:write).and_return(true)
      allow(redis_store).to receive(:respond_to?).with(:increment).and_return(true)
      allow(redis_store).to receive(:respond_to?).with(:with_lock).and_return(true)
      allow(redis_store).to receive(:respond_to?).with(:options).and_return(true)
      allow(redis_store).to receive(:options).and_return({ namespace: 'test', compress: true })

      allow(Rails).to receive(:cache).and_return(redis_store)
      strategy = described_class.new
      expect(strategy.coordination_mode).to eq(:distributed_atomic)
    end

    it 'selects distributed_basic for atomic but no locking' do
      memcache_store = double('MemCacheStore', class: double(name: 'ActiveSupport::Cache::MemCacheStore'))
      allow(memcache_store).to receive(:respond_to?).with(:read).and_return(true)
      allow(memcache_store).to receive(:respond_to?).with(:write).and_return(true)
      allow(memcache_store).to receive(:respond_to?).with(:increment).and_return(true)
      allow(memcache_store).to receive(:respond_to?).with(:with_lock).and_return(false)
      allow(memcache_store).to receive(:respond_to?).with(:options).and_return(true)
      allow(memcache_store).to receive(:options).and_return({ namespace: 'test' })

      allow(Rails).to receive(:cache).and_return(memcache_store)
      strategy = described_class.new
      expect(strategy.coordination_mode).to eq(:distributed_basic)
    end

    it 'selects local_only for memory stores' do
      memory_store = double('MemoryStore', class: double(name: 'ActiveSupport::Cache::MemoryStore'))
      allow(memory_store).to receive(:respond_to?).with(:read).and_return(true)
      allow(memory_store).to receive(:respond_to?).with(:write).and_return(true)
      allow(memory_store).to receive(:respond_to?).with(:increment).and_return(false)
      allow(memory_store).to receive(:respond_to?).with(:with_lock).and_return(false)
      allow(memory_store).to receive(:respond_to?).with(:options).and_return(false)

      allow(Rails).to receive(:cache).and_return(memory_store)
      strategy = described_class.new
      expect(strategy.coordination_mode).to eq(:local_only)
    end
  end

  describe 'caching behavior' do
    it 'caches strategy instances for the same store class' do
      redis_store1 = double('RedisCacheStore1', class: double(name: 'ActiveSupport::Cache::RedisCacheStore'))
      redis_store2 = double('RedisCacheStore2', class: double(name: 'ActiveSupport::Cache::RedisCacheStore'))

      [redis_store1, redis_store2].each do |store|
        allow(store).to receive(:respond_to?).with(:read).and_return(true)
        allow(store).to receive(:respond_to?).with(:write).and_return(true)
        allow(store).to receive(:respond_to?).with(:increment).and_return(true)
        allow(store).to receive(:respond_to?).with(:with_lock).and_return(true)
        allow(store).to receive(:respond_to?).with(:options).and_return(true)
        allow(store).to receive(:options).and_return({ namespace: 'test', compress: true })
      end

      allow(Rails).to receive(:cache).and_return(redis_store1)
      strategy1 = described_class.new

      allow(Rails).to receive(:cache).and_return(redis_store2)
      strategy2 = described_class.new

      # Should have same capabilities due to caching
      expect(strategy1.capabilities).to eq(strategy2.capabilities)
      expect(strategy1.coordination_mode).to eq(strategy2.coordination_mode)
    end
  end

  describe 'error handling' do
    context 'when capability detection fails' do
      before do
        allow(mock_store).to receive(:class).and_return(double(name: 'ActiveSupport::Cache::MemoryStore'))
        # Make the capability detection fail by having class access raise an error
        allow(mock_store).to receive(:class).and_raise(StandardError.new('Detection failed'))
      end

      it 'falls back to default capabilities and logs error' do
        allow(Rails).to receive(:cache).and_return(mock_store)

        expect_any_instance_of(described_class).to receive(:log_structured).with(
          :warn,
          'Rails.cache unavailable, using fallback configuration',
          hash_including(:error, :instance_id)
        ).at_least(:once)

        # No log_strategy_detection call when exception occurs (early return)
        strategy = described_class.new
        expect(strategy.coordination_mode).to eq(:local_only)
      end
    end

    context 'when custom detector fails' do
      it 'logs warning and continues with built-in detection' do
        failing_detector = ->(store) { raise StandardError.new('Custom detector failed') }

        described_class.register_detector(/FailingStore/, failing_detector)

        failing_store = double('FailingStore', class: double(name: 'Company::FailingStore'))
        allow(failing_store).to receive(:respond_to?).with(:read).and_return(true)
        allow(failing_store).to receive(:respond_to?).with(:write).and_return(true)
        allow(failing_store).to receive(:respond_to?).with(:increment).and_return(false)
        allow(failing_store).to receive(:respond_to?).with(:with_lock).and_return(false)
        allow(failing_store).to receive(:respond_to?).with(:options).and_return(false)

        allow(Rails).to receive(:cache).and_return(failing_store)

        expect_any_instance_of(described_class).to receive(:log_structured).with(
          :warn,
          'Custom detector failed',
          hash_including(:pattern, :error, :store_class)
        )

        # Also expect the normal strategy detection log
        expect_any_instance_of(described_class).to receive(:log_structured).with(
          :info,
          'Cache strategy detected',
          hash_including(:store_class, :coordination_strategy, :capabilities, :instance_id)
        )

        strategy = described_class.new
        expect(strategy.coordination_mode).to eq(:local_only) # Should fall back to built-in detection
      end
    end
  end

  describe 'instance management' do
    it 'generates unique instance IDs' do
      allow(mock_store).to receive(:class).and_return(double(name: 'ActiveSupport::Cache::MemoryStore'))
      allow(mock_store).to receive(:respond_to?).with(:increment).and_return(false)
      allow(mock_store).to receive(:respond_to?).with(:with_lock).and_return(false)
      allow(mock_store).to receive(:respond_to?).with(:options).and_return(false)

      allow(Rails).to receive(:cache).and_return(mock_store)
      strategy1 = described_class.new
      strategy2 = described_class.new

      expect(strategy1.instance_id).to eq(strategy2.instance_id) # Same process, same ID
      expect(strategy1.instance_id).to match(/\A.+-\d+\z/) # hostname-pid format
    end
  end

  describe 'capability export' do
    it 'exports capabilities for backward compatibility' do
      redis_store = double('RedisCacheStore', class: double(name: 'ActiveSupport::Cache::RedisCacheStore'))
      allow(redis_store).to receive(:respond_to?).with(:read).and_return(true)
      allow(redis_store).to receive(:respond_to?).with(:write).and_return(true)
      allow(redis_store).to receive(:respond_to?).with(:increment).and_return(true)
      allow(redis_store).to receive(:respond_to?).with(:with_lock).and_return(true)
      allow(redis_store).to receive(:respond_to?).with(:options).and_return(false)

      allow(Rails).to receive(:cache).and_return(redis_store)
      strategy = described_class.new
      capabilities = strategy.export_capabilities

      expect(capabilities).to include(
        distributed: true,
        atomic_increment: true,
        locking: true,
        ttl_inspection: true,
        key_transformation: true,
        store_class: 'ActiveSupport::Cache::RedisCacheStore'
      )
    end
  end

  describe 'detector registry' do
    it 'maintains detector registry across calls' do
      custom_detector = ->(store) { { custom: true } }

      described_class.register_detector(/Custom/, custom_detector)

      # Accessing registry should maintain the registered detector
      registry = Tasker::DetectorRegistry.instance
      detectors = registry.custom_detectors
      expect(detectors.keys.first.to_s).to include('Custom')
    end

    it 'clears detectors when requested' do
      custom_detector = ->(store) { { custom: true } }

      described_class.register_detector(/Custom/, custom_detector)
      described_class.clear_detectors!

      registry = Tasker::DetectorRegistry.instance
      detectors = registry.custom_detectors
      expect(detectors).to be_empty
    end
  end

  describe 'constants' do
    describe 'DISTRIBUTED_CACHE_STORES' do
      it 'includes official Rails distributed cache stores' do
        expect(described_class::DISTRIBUTED_CACHE_STORES).to eq([
          'ActiveSupport::Cache::RedisCacheStore',
          'ActiveSupport::Cache::MemCacheStore',
          'SolidCache::Store'
        ])
      end

      it 'is frozen for performance' do
        expect(described_class::DISTRIBUTED_CACHE_STORES).to be_frozen
      end
    end

    describe 'ATOMIC_INCREMENT_STORES' do
      it 'includes stores that support atomic increment operations' do
        expect(described_class::ATOMIC_INCREMENT_STORES).to eq([
          'ActiveSupport::Cache::RedisCacheStore',
          'ActiveSupport::Cache::MemCacheStore',
          'SolidCache::Store'
        ])
      end

      it 'is frozen for performance' do
        expect(described_class::ATOMIC_INCREMENT_STORES).to be_frozen
      end
    end

    describe 'LOCKING_CAPABLE_STORES' do
      it 'includes stores that support distributed locking' do
        expect(described_class::LOCKING_CAPABLE_STORES).to eq([
          'ActiveSupport::Cache::RedisCacheStore',
          'SolidCache::Store'
        ])
      end

      it 'is frozen for performance' do
        expect(described_class::LOCKING_CAPABLE_STORES).to be_frozen
      end
    end

    describe 'LOCAL_CACHE_STORES' do
      it 'includes local-only cache stores' do
        expect(described_class::LOCAL_CACHE_STORES).to eq([
          'ActiveSupport::Cache::MemoryStore',
          'ActiveSupport::Cache::FileStore',
          'ActiveSupport::Cache::NullStore'
        ])
      end

      it 'is frozen for performance' do
        expect(described_class::LOCAL_CACHE_STORES).to be_frozen
      end
    end
  end

  describe 'hybrid detection system' do
    context 'with declared capabilities (Priority 1)' do
      let(:custom_cache_store_class) do
        Class.new(ActiveSupport::Cache::Store) do
          include Tasker::CacheCapabilities

          supports_distributed_caching!
          supports_atomic_increment!
          declare_cache_capability(:custom_feature, true)
          declare_cache_capability(:compression_support, false) # Override default
        end
      end

      let(:custom_store) { custom_cache_store_class.new }

      it 'uses declared capabilities as highest priority' do
        allow(Rails).to receive(:cache).and_return(custom_store)
        strategy = described_class.new

        expect(strategy.supports?(:distributed)).to be(true)
        expect(strategy.supports?(:atomic_increment)).to be(true)
        expect(strategy.supports?(:custom_feature)).to be(true)
        expect(strategy.supports?(:compression_support)).to be(false)
      end

      it 'logs declared capability usage' do
        allow(Rails).to receive(:cache).and_return(custom_store)

        # The declared capabilities logging happens with debug level
        expect_any_instance_of(described_class).to receive(:log_structured).with(
          :debug,
          'Using declared cache capabilities',
          hash_including(:store_class, :declared_capabilities)
        )

        # Also expect the normal strategy detection log
        expect_any_instance_of(described_class).to receive(:log_structured).with(
          :info,
          'Cache strategy detected',
          hash_including(:store_class, :coordination_strategy, :capabilities, :instance_id)
        )

        described_class.new
      end
    end

    context 'with built-in store constants (Priority 2)' do
             it 'detects Redis cache store capabilities' do
         allow(Rails).to receive(:cache).and_return(redis_store)
         allow(redis_store).to receive(:respond_to?).and_return(false)
         allow(redis_store).to receive(:respond_to?).with(:read).and_return(true)
         allow(redis_store).to receive(:respond_to?).with(:write).and_return(true)
         strategy = described_class.new

         expect(strategy.supports?(:distributed)).to be(true)
         expect(strategy.supports?(:atomic_increment)).to be(true)
         expect(strategy.supports?(:locking)).to be(true)
         expect(strategy.coordination_mode).to eq(:distributed_atomic)
       end

       it 'detects Memcache store capabilities' do
         allow(Rails).to receive(:cache).and_return(memcache_store)
         allow(memcache_store).to receive(:respond_to?).and_return(false)
         allow(memcache_store).to receive(:respond_to?).with(:read).and_return(true)
         allow(memcache_store).to receive(:respond_to?).with(:write).and_return(true)
         strategy = described_class.new

         expect(strategy.supports?(:distributed)).to be(true)
         expect(strategy.supports?(:atomic_increment)).to be(true)
         expect(strategy.supports?(:locking)).to be(false) # Memcache doesn't support locking
         expect(strategy.coordination_mode).to eq(:distributed_basic)
       end

       it 'detects SolidCache store capabilities' do
         allow(Rails).to receive(:cache).and_return(solid_cache_store)
         allow(solid_cache_store).to receive(:respond_to?).and_return(false)
         allow(solid_cache_store).to receive(:respond_to?).with(:read).and_return(true)
         allow(solid_cache_store).to receive(:respond_to?).with(:write).and_return(true)
         strategy = described_class.new

         expect(strategy.supports?(:distributed)).to be(true)
         expect(strategy.supports?(:atomic_increment)).to be(true)
         expect(strategy.supports?(:locking)).to be(true)
         expect(strategy.coordination_mode).to eq(:distributed_atomic)
       end

       it 'detects local cache stores' do
         allow(Rails).to receive(:cache).and_return(memory_store)
         strategy = described_class.new

         expect(strategy.supports?(:distributed)).to be(false)
         expect(strategy.supports?(:atomic_increment)).to be(false)
         expect(strategy.supports?(:locking)).to be(false)
         expect(strategy.coordination_mode).to eq(:local_only)
       end
    end

    context 'with custom detectors (Priority 3)' do
      let(:unknown_store) { double('UnknownStore', class: double(name: 'MyCustom::CacheStore')) }

      before do
        described_class.register_detector(/MyCustom/, ->(store) {
          { distributed: true, custom_feature: 'advanced' }
        })
      end

      it 'applies custom detectors for unknown stores' do
        allow(unknown_store).to receive(:respond_to?).and_return(false)
        allow(unknown_store).to receive(:respond_to?).with(:read).and_return(true)
        allow(unknown_store).to receive(:respond_to?).with(:write).and_return(true)
        allow(Rails).to receive(:cache).and_return(unknown_store)
        strategy = described_class.new

        expect(strategy.supports?(:distributed)).to be(true)
        expect(strategy.supports?(:custom_feature)).to eq('advanced')
      end

      it 'custom detectors do not override declared capabilities' do
        custom_store_with_declarations = Class.new(ActiveSupport::Cache::Store) do
          include Tasker::CacheCapabilities
          declare_cache_capability(:distributed, false) # Explicitly declare as false
        end

        # Set class name to match custom detector pattern
        allow(custom_store_with_declarations).to receive(:name).and_return('MyCustom::DeclaredStore')
        store_instance = custom_store_with_declarations.new

        allow(Rails).to receive(:cache).and_return(store_instance)
        strategy = described_class.new

        # Declared capability should win over custom detector
        expect(strategy.supports?(:distributed)).to be(false)
        expect(strategy.supports?(:custom_feature)).to eq('advanced') # From detector
      end
    end

    context 'with runtime detection fallback (Priority 4)' do
      let(:unknown_redis_like_store) do
        double('UnknownRedisLikeStore',
          class: double(name: 'SomeLibrary::RedisBasedCache'),
          respond_to?: false
        )
      end

      it 'falls back to runtime pattern detection' do
        allow(unknown_redis_like_store).to receive(:respond_to?).and_return(false)
        allow(unknown_redis_like_store).to receive(:respond_to?).with(:read).and_return(true)
        allow(unknown_redis_like_store).to receive(:respond_to?).with(:write).and_return(true)
        allow(Rails).to receive(:cache).and_return(unknown_redis_like_store)
        strategy = described_class.new

        # Unknown stores get conservative defaults (no pattern matching for reliability)
        expect(strategy.supports?(:distributed)).to be(false)
        expect(strategy.supports?(:atomic_increment)).to be(false)
        expect(strategy.coordination_mode).to eq(:local_only)
      end

      it 'provides conservative defaults for completely unknown stores' do
        unknown_store = double('CompletelyUnknownStore',
          class: double(name: 'Unknown::Store'),
          respond_to?: false
        )

        allow(Rails).to receive(:cache).and_return(unknown_store)
        strategy = described_class.new

        expect(strategy.supports?(:distributed)).to be(false)
        expect(strategy.supports?(:atomic_increment)).to be(false)
        expect(strategy.supports?(:locking)).to be(false)
        expect(strategy.coordination_mode).to eq(:local_only)
      end
    end
  end

  describe 'priority order integration' do
    it 'demonstrates complete priority hierarchy' do
      # Clear strategy cache before this specific test to prevent interference
      registry = Tasker::DetectorRegistry.instance
      registry.instance_variable_set(:@strategy_cache, {})

      # Create a store that would match multiple detection methods
      complex_store_class = Class.new(ActiveSupport::Cache::Store) do
        include Tasker::CacheCapabilities

        # Declare some capabilities explicitly (Priority 1)
        declare_cache_capability(:distributed, false) # Override what constants would say
        supports_atomic_increment! # Explicit declaration
      end

      # Make it look like a Redis store to built-in constants (Priority 2)
      allow(complex_store_class).to receive(:name).and_return('ActiveSupport::Cache::RedisCacheStore')

      # Register a custom detector that would match (Priority 3)
      described_class.register_detector(/Redis/, ->(store) {
        { locking: true, custom_feature: 'from_detector' }
      })

      store_instance = complex_store_class.new
      allow(store_instance).to receive(:respond_to?).and_return(false)
      allow(store_instance).to receive(:respond_to?).with(:read).and_return(true)
      allow(store_instance).to receive(:respond_to?).with(:write).and_return(true)
      allow(store_instance).to receive(:respond_to?).with(:with_lock).and_return(true)

      allow(Rails).to receive(:cache).and_return(store_instance)
      strategy = described_class.new

      # Priority 1: Declared capabilities win
      expect(strategy.supports?(:distributed)).to be(false) # Declared override
      expect(strategy.supports?(:atomic_increment)).to be(true) # Declared

      # Priority 2: Built-in constants fill gaps
      expect(strategy.supports?(:ttl_inspection)).to be(true) # From constants (Redis supports TTL)

      # Priority 3: Custom detector fills remaining gaps
      expect(strategy.supports?(:custom_feature)).to eq('from_detector')

      # Priority 4: Runtime detection for anything else
      expect(strategy.supports?(:locking)).to be(true) # Runtime detection (respond_to?)
    end
  end

  describe 'backward compatibility' do
    it 'maintains existing API' do
      allow(Rails).to receive(:cache).and_return(redis_store)
      strategy = described_class.new

      expect(strategy).to respond_to(:supports?)
      expect(strategy).to respond_to(:export_capabilities)
      expect(strategy).to respond_to(:coordination_mode)
      expect(strategy).to respond_to(:store_class_name)
    end

    it 'export_capabilities returns expected format' do
      allow(Rails).to receive(:cache).and_return(memory_store)
      strategy = described_class.new
      capabilities = strategy.export_capabilities

      expect(capabilities).to be_a(Hash)
      expect(capabilities).to have_key(:distributed)
      expect(capabilities).to have_key(:atomic_increment)
      expect(capabilities).to have_key(:locking)
      expect(capabilities).to have_key(:store_class)
    end
  end

  describe 'error handling' do
    it 'handles store class name detection errors gracefully' do
      broken_store = double('BrokenStore')
      allow(broken_store).to receive(:class).and_raise(StandardError.new('Broken'))

      allow(Rails).to receive(:cache).and_return(broken_store)
      expect {
        strategy = described_class.new
        expect(strategy.store_class_name).to eq('Unknown')
      }.not_to raise_error
    end

    it 'handles declared capability detection errors gracefully' do
      broken_declared_store = double('BrokenDeclaredStore')
      broken_class = double('BrokenClass')
      allow(broken_declared_store).to receive(:class).and_return(broken_class)
      allow(broken_class).to receive(:name).and_return('BrokenStore')
      allow(broken_class).to receive(:respond_to?).with(:declared_cache_capabilities).and_return(true)
      allow(broken_class).to receive(:declared_cache_capabilities).and_raise(StandardError.new('Broken'))

      allow(Rails).to receive(:cache).and_return(broken_declared_store)
      expect {
        strategy = described_class.new
        expect(strategy.supports?(:distributed)).to be(false) # Falls back to safe defaults
      }.not_to raise_error
    end
  end

  describe 'performance characteristics' do
    it 'caches strategy instances for same store class' do
      allow(Rails).to receive(:cache).and_return(memory_store)
      strategy1 = described_class.new

      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
      strategy2 = described_class.new

      # Both should have same capabilities (cached)
      expect(strategy1.capabilities).to eq(strategy2.capabilities)
      expect(strategy1.coordination_mode).to eq(strategy2.coordination_mode)
    end

    it 'frozen constants provide O(1) lookup' do
      # Test that constants are used for built-in stores
      expect(described_class::DISTRIBUTED_CACHE_STORES.include?('ActiveSupport::Cache::RedisCacheStore')).to be(true)
      expect(described_class::ATOMIC_INCREMENT_STORES.include?('ActiveSupport::Cache::MemCacheStore')).to be(true)
      expect(described_class::LOCKING_CAPABLE_STORES.include?('SolidCache::Store')).to be(true)
    end
  end
end
