# frozen_string_literal: true

module CacheStoreHelpers
  # Test helper for dynamically swapping Rails cache stores
  # Enables testing cache detection and sync strategies across different backends

  # Available cache stores for testing
  CACHE_STORES = {
    redis_store: -> { ActiveSupport::Cache::RedisCacheStore.new(url: 'redis://localhost:6379/1') },
    memcache_store: -> { ActiveSupport::Cache::MemCacheStore.new('localhost:11211') },
    memory_store: -> { ActiveSupport::Cache::MemoryStore.new },
    file_store: -> { ActiveSupport::Cache::FileStore.new(Rails.root.join('tmp', 'cache')) },
    null_store: -> { ActiveSupport::Cache::NullStore.new },
    solid_cache_store: -> {
      # Create a Solid Cache store if available
      if defined?(SolidCache)
        SolidCache::Store.new
      else
        # Fallback to a mock that behaves like Solid Cache
        mock_solid_cache_store
      end
    }
  }.freeze

  # Temporarily swap the Rails cache store for testing
  #
  # @param store_type [Symbol] Type of cache store to use
  # @yield Block to execute with the swapped cache store
  # @example
  #   with_cache_store(:redis_store) do
  #     # Test code that uses Rails.cache
  #   end
  def with_cache_store(store_type)
    raise ArgumentError, "Unknown cache store: #{store_type}" unless CACHE_STORES.key?(store_type)

    original_cache = Rails.cache
    new_cache = CACHE_STORES[store_type].call

    Rails.cache = new_cache

    yield
  ensure
    Rails.cache = original_cache
  end

  # Test cache store capabilities without requiring actual cache servers
  #
  # @param store_type [Symbol] Type of cache store to mock
  # @return [Hash] Expected capabilities for the store type
  def expected_cache_capabilities(store_type)
    case store_type
    when :redis_store
      {
        distributed: true,
        atomic_increment: true,
        locking: true,
        ttl_inspection: true,
        store_class: 'ActiveSupport::Cache::RedisCacheStore',
        key_transformation: true,
        namespace_support: true,
        compression_support: true
      }
    when :memcache_store
      {
        distributed: true,
        atomic_increment: true,
        locking: false,
        ttl_inspection: true,
        store_class: 'ActiveSupport::Cache::MemCacheStore',
        key_transformation: true,
        namespace_support: true,
        compression_support: true
      }
    when :memory_store
      {
        distributed: false,
        atomic_increment: false,
        locking: false,
        ttl_inspection: false,
        store_class: 'ActiveSupport::Cache::MemoryStore',
        key_transformation: true,
        namespace_support: false,
        compression_support: false
      }
    when :file_store
      {
        distributed: false,
        atomic_increment: false,
        locking: false,
        ttl_inspection: false,
        store_class: 'ActiveSupport::Cache::FileStore',
        key_transformation: true,
        namespace_support: false,
        compression_support: false
      }
    when :null_store
      {
        distributed: false,
        atomic_increment: false,
        locking: false,
        ttl_inspection: false,
        store_class: 'ActiveSupport::Cache::NullStore',
        key_transformation: true,
        namespace_support: false,
        compression_support: false
      }
         when :solid_cache_store
       {
         distributed: true,
         atomic_increment: true,
         locking: true,
         ttl_inspection: true,
         store_class: 'SolidCache::Store',
         key_transformation: true,
         namespace_support: false,
         compression_support: false
       }
    else
      raise ArgumentError, "Unknown cache store type: #{store_type}"
    end
  end

  # Expected sync strategy for a given cache store type
  #
  # @param store_type [Symbol] Type of cache store
  # @return [Symbol] Expected sync strategy
  def expected_sync_strategy(store_type)
    case store_type
    when :redis_store
      :distributed_atomic
    when :memcache_store
      :distributed_basic
    when :memory_store, :file_store, :null_store
      :local_only
         when :solid_cache_store
       :distributed_atomic
    else
      raise ArgumentError, "Unknown cache store type: #{store_type}"
    end
  end

  # Mock a cache store with specific capabilities for testing
  #
  # @param capabilities [Hash] Capabilities to mock
  # @return [Double] Mocked cache store
  def mock_cache_store_with_capabilities(capabilities)
    store = double('MockCacheStore')

    # Mock basic cache store interface
    allow(store).to receive(:read)
    allow(store).to receive(:write)
    allow(store).to receive(:delete)
    allow(store).to receive(:clear)

    # Mock capability detection methods
    allow(store).to receive(:class).and_return(double(name: capabilities[:store_class]))
    allow(store).to receive(:respond_to?).with(:increment).and_return(capabilities[:atomic_increment])
    allow(store).to receive(:respond_to?).with(:options).and_return(capabilities[:namespace_support])

    if capabilities[:namespace_support]
      options = {}
      options[:namespace] = 'test' if capabilities[:namespace_support]
      options[:compress] = true if capabilities[:compression_support]
      allow(store).to receive(:options).and_return(options)
    end

    store
  end

  # Create a real cache store instance for integration testing
  #
  # @param store_type [Symbol] Type of cache store to create
  # @return [ActiveSupport::Cache::Store] Real cache store instance
  def create_cache_store(store_type)
    CACHE_STORES[store_type].call
  rescue StandardError => e
    skip "Cannot create #{store_type}: #{e.message}"
  end

  # Clean up cache store after testing
  #
  # @param store [ActiveSupport::Cache::Store] Cache store to clean
  def cleanup_cache_store(store)
    store.clear if store.respond_to?(:clear)
  rescue StandardError => e
    # Ignore cleanup errors
    Rails.logger&.debug("Cache cleanup failed: #{e.message}")
  end

  private

  # Create a mock Solid Cache store for testing when gem is not available
  def mock_solid_cache_store
    store = double('SolidCacheStore')
    allow(store).to receive(:class).and_return(double(name: 'SolidCache::Store'))
    allow(store).to receive(:read)
    allow(store).to receive(:write)
    allow(store).to receive(:delete)
    allow(store).to receive(:clear)
    allow(store).to receive(:increment)
    allow(store).to receive(:respond_to?).with(:read).and_return(true)
    allow(store).to receive(:respond_to?).with(:write).and_return(true)
    allow(store).to receive(:respond_to?).with(:increment).and_return(true)
    allow(store).to receive(:respond_to?).with(:with_lock).and_return(false)
    allow(store).to receive(:respond_to?).with(:options).and_return(false)
    store
  end

  public
end

# Include in RSpec configuration
RSpec.configure do |config|
  config.include CacheStoreHelpers, type: :cache_store

  # Auto-include for telemetry specs that need cache testing
  config.include CacheStoreHelpers, file_path: %r{spec/lib/tasker/telemetry}
end
