# frozen_string_literal: true

require 'singleton'
require 'tasker/cache_capabilities'

module Tasker
  # Unified cache capability detection and strategy management
  #
  # This class consolidates cache store introspection from MetricsBackend and
  # IntelligentCacheManager into a single, comprehensive system that:
  #
  # 1. Detects capabilities of all major Rails cache stores
  # 2. Supports Solid Cache and other modern Rails cache stores
  # 3. Provides extensibility for custom cache implementations
  # 4. Offers a consistent API for cache strategy selection
  #
  # **Phase 2.1.1 Enhancement: Hybrid Cache Store Detection System**
  # Combines frozen constants for built-in Rails cache stores with declared
  # capabilities for custom cache stores, creating a robust and extensible architecture.
  #
  # Detection Priority Order:
  # 1. Declared capabilities (highest priority) - explicit developer declarations
  # 2. Built-in store constants - fast, reliable detection for known stores
  # 3. Custom detectors - pattern-based registration for legacy compatibility
  # 4. Runtime detection - conservative fallback for unknown stores
  #
  # @example Basic usage
  #   strategy = Tasker::CacheStrategy.detect
  #   strategy.coordination_mode  # => :distributed_atomic
  #   strategy.supports?(:locking) # => true
  #
  # @example Custom detector registration
  #   Tasker::CacheStrategy.register_detector(/MyCache/, ->(store) {
  #     { distributed: true, custom_feature: true }
  #   })
  #
  # @example Custom cache store with capabilities
  #   class MyAwesomeCacheStore < ActiveSupport::Cache::Store
  #     include Tasker::CacheCapabilities
  #     supports_distributed_caching!
  #     supports_atomic_increment!
  #   end
  #
  #   # Configure Rails to use your custom store
  #   Rails.application.configure do
  #     config.cache_store = MyAwesomeCacheStore.new
  #   end
  #
  # @example Direct instantiation
  #   strategy = Tasker::CacheStrategy.new
  class CacheStrategy
    include Tasker::Concerns::StructuredLogging

    # Cache store coordination strategies
    COORDINATION_STRATEGIES = {
      distributed_atomic: 'Full distributed coordination with atomic operations',
      distributed_basic: 'Basic distributed coordination with read-modify-write',
      local_only: 'Local-only coordination for single-process deployments'
    }.freeze

    # ✅ CONSTANTS: Official Rails cache store class names (validated against Rails 8.0+ docs)
    # These provide O(1) lookup performance for built-in Rails cache stores
    DISTRIBUTED_CACHE_STORES = %w[
      ActiveSupport::Cache::RedisCacheStore
      ActiveSupport::Cache::MemCacheStore
      SolidCache::Store
    ].freeze

    ATOMIC_INCREMENT_STORES = %w[
      ActiveSupport::Cache::RedisCacheStore
      ActiveSupport::Cache::MemCacheStore
      SolidCache::Store
    ].freeze

    LOCKING_CAPABLE_STORES = %w[
      ActiveSupport::Cache::RedisCacheStore
      SolidCache::Store
    ].freeze

    LOCAL_CACHE_STORES = %w[
      ActiveSupport::Cache::MemoryStore
      ActiveSupport::Cache::FileStore
      ActiveSupport::Cache::NullStore
    ].freeze

    attr_reader :store, :store_class_name, :capabilities, :coordination_mode, :instance_id

    # Detect cache strategy for the current Rails.cache store
    #
    # @return [Tasker::CacheStrategy] Strategy instance for Rails.cache
    def self.detect
      new
    end

    # Register a custom cache store detector
    #
    # @param pattern [Regexp, String] Pattern to match store class names
    # @param detector [Proc] Detector that returns capabilities hash
    def self.register_detector(pattern, detector)
      DetectorRegistry.instance.register_detector(pattern, detector)
    end

    # Clear all registered detectors (primarily for testing)
    def self.clear_detectors!
      DetectorRegistry.instance.clear_detectors!
    end

    # Create a strategy for the current Rails.cache store
    #
    # The cache strategy always analyzes Rails.cache, which is the single source
    # of truth for caching in Rails applications. Custom cache stores should be
    # configured through Rails.cache and declare their capabilities via the
    # CacheCapabilities module.
    def initialize
      @detector_registry = DetectorRegistry.instance
      @instance_id = generate_instance_id

          # Handle Rails.cache unavailability gracefully
    begin
      @store = Rails.cache
      @store_class_name = @store.class.name
    rescue StandardError => e
      log_structured(:warn, 'Rails.cache unavailable, using fallback configuration',
        error: e.message,
        instance_id: @instance_id
      )
      @store = nil
      @store_class_name = 'Unknown'
      @capabilities = default_capabilities
      @coordination_mode = :local_only
      return
    end

    # Generate cache key that includes store configuration
    cache_key = generate_cache_key(@store, @store_class_name)

    # Check for cached strategy first
    cached = @detector_registry.cached_strategy_for(cache_key)
    if cached
      @capabilities = cached.capabilities
      @coordination_mode = cached.coordination_mode
    else
      # Detect capabilities with error handling
      begin
        @capabilities = detect_capabilities
        @coordination_mode = select_coordination_strategy

        # Cache this strategy instance
        @detector_registry.cache_strategy_for(cache_key, self)
      rescue StandardError => e
        log_structured(:warn, 'Cache detection failed',
          error: e.message,
          store_class: @store_class_name,
          instance_id: @instance_id
        )
        log_structured(:warn, 'Falling back to local-only mode')
        @store_class_name = 'Unknown'
        @capabilities = default_capabilities
        @coordination_mode = :local_only
        return
      end
    end

    log_strategy_detection
    end

    # Check if store supports a specific capability
    #
    # @param capability [Symbol] Capability to check (:distributed, :atomic_increment, etc.)
    # @return [Boolean] True if capability is supported
    def supports?(capability)
      @capabilities[capability] || false
    end

    # Export capabilities for backward compatibility
    #
    # @return [Hash] Hash of capabilities for legacy integrations
    def export_capabilities
      @capabilities.dup
    end

    private

    # Generate unique instance identifier for distributed coordination
    #
    # @return [String] Hostname-PID identifier
    def generate_instance_id
      hostname = begin
        ENV['HOSTNAME'] || Socket.gethostname
      rescue StandardError
        'unknown'
      end
      "#{hostname}-#{Process.pid}"
    end

    # Generate cache key that includes store configuration
    #
    # @param store [ActiveSupport::Cache::Store] Rails cache store
    # @param store_class_name [String] Store class name
    # @return [String] Cache key that includes relevant configuration
    def generate_cache_key(store, store_class_name)
      key_parts = [store_class_name]

      # Include namespace in cache key if present
      if store.respond_to?(:options) && store.options.key?(:namespace)
        key_parts << "namespace:#{store.options[:namespace]}"
      end

      # Include compression in cache key if present
      if store.respond_to?(:options) && store.options.key?(:compress)
        key_parts << "compress:#{store.options[:compress]}"
      end

      key_parts.join('|')
    rescue StandardError
      # Fallback to just class name if options access fails
      store_class_name
    end

    # Detect cache store capabilities using hybrid detection system
    #
    # Detection Priority Order:
    # 1. Declared capabilities (highest priority) - explicit developer declarations
    # 2. Built-in store constants - fast, reliable detection for known stores
    # 3. Custom detectors - pattern-based registration for legacy compatibility
    # 4. Runtime detection - conservative fallback for unknown stores
    #
    # @return [Hash] Detected capabilities
    def detect_capabilities
      return default_capabilities unless rails_cache_available?

      capabilities = {}

      # Priority 1: Check for declared capabilities via CacheCapabilities module
      declared_capabilities = detect_declared_capabilities
      if declared_capabilities.any?
        log_structured(:debug, 'Using declared cache capabilities',
          store_class: @store_class_name,
          declared_capabilities: declared_capabilities
        )
        capabilities.merge!(declared_capabilities)
      end

      # Priority 2: Apply custom detectors (higher priority than built-in constants)
      custom_capabilities = apply_custom_detectors
      capabilities.merge!(custom_capabilities) { |_key, declared, custom| declared.nil? ? custom : declared }

      # Priority 3: Use built-in store constants for remaining capabilities
      builtin_capabilities = detect_builtin_store_capabilities
      capabilities.merge!(builtin_capabilities) { |_key, existing, builtin| existing.nil? ? builtin : existing }

      # Priority 4: Runtime detection fallback for any missing capabilities
      runtime_capabilities = detect_runtime_capabilities
      capabilities.merge!(runtime_capabilities) { |_key, existing, runtime| existing.nil? ? runtime : existing }

      # Ensure all expected capabilities are present
      capabilities.merge!(default_capabilities) { |_key, detected, default| detected.nil? ? default : detected }

      capabilities
    rescue StandardError => e
      log_structured(:error, 'Cache capability detection failed',
        error: e.message,
        store_class: @store_class_name,
        instance_id: @instance_id
      )
      default_capabilities
    end

    # Priority 1: Detect capabilities declared via CacheCapabilities module
    #
    # @return [Hash] Declared capabilities from CacheCapabilities module
    def detect_declared_capabilities
      return {} unless @store.class.respond_to?(:declared_cache_capabilities)

      declared = @store.class.declared_cache_capabilities
      return {} unless declared.is_a?(Hash) && declared.any?

      # Convert to our standard capability format
      capabilities = {}
      declared.each do |capability, supported|
        capabilities[capability.to_sym] = supported
      end

      capabilities
    rescue StandardError => e
      log_structured(:warn, 'Failed to detect declared capabilities',
        error: e.message,
        store_class: @store_class_name
      )
      {}
    end

    # Priority 3: Detect capabilities using built-in store constants
    #
    # @return [Hash] Capabilities detected from frozen constants
    def detect_builtin_store_capabilities
      capabilities = {
        distributed: DISTRIBUTED_CACHE_STORES.include?(@store_class_name),
        atomic_increment: ATOMIC_INCREMENT_STORES.include?(@store_class_name),
        locking: LOCKING_CAPABLE_STORES.include?(@store_class_name),
        ttl_inspection: DISTRIBUTED_CACHE_STORES.include?(@store_class_name), # Most distributed stores support TTL
        namespace_support: nil, # Will be detected at runtime
        compression_support: nil, # Will be detected at runtime
        key_transformation: true, # All Rails cache stores transform keys
        store_class: @store_class_name
      }

      # Remove nil values so they can be filled by lower-priority detection
      capabilities.compact
    end

    # Priority 4: Runtime detection fallback for missing capabilities
    #
    # Uses our frozen constants plus runtime introspection for non-capability features
    # @return [Hash] Runtime-detected capabilities
    def detect_runtime_capabilities
      capabilities = {
        # Use frozen constants (much more reliable than pattern matching)
        distributed: DISTRIBUTED_CACHE_STORES.include?(@store_class_name),
        atomic_increment: ATOMIC_INCREMENT_STORES.include?(@store_class_name),
        locking: LOCKING_CAPABLE_STORES.include?(@store_class_name),
        ttl_inspection: DISTRIBUTED_CACHE_STORES.include?(@store_class_name), # Most distributed stores support TTL
        # These require actual runtime introspection
        namespace_support: namespace_support?(@store),
        compression_support: compression_support?(@store),
        key_transformation: true, # All Rails cache stores transform keys
        store_class: @store_class_name
      }

      capabilities
    end

    # Priority 2: Apply custom detectors to the store
    #
    # @return [Hash] Custom capabilities detected
    def apply_custom_detectors
      custom_capabilities = {}

      @detector_registry.custom_detectors.each do |pattern, detector|
        if pattern.is_a?(Regexp) ? pattern.match?(@store_class_name) : @store_class_name.include?(pattern.to_s)
          begin
            detected = detector.call(@store)
            custom_capabilities.merge!(detected) if detected.is_a?(Hash)
          rescue StandardError => e
            log_structured(:warn, 'Custom detector failed',
              pattern: pattern.inspect,
              error: e.message,
              store_class: @store_class_name
            )
          end
        end
      end

      custom_capabilities
    end

    # Check if cache store supports namespacing
    #
    # @param store [ActiveSupport::Cache::Store] Rails cache store
    # @return [Boolean] True if namespace is supported
    def namespace_support?(store)
      store.respond_to?(:options) && store.options.key?(:namespace)
    rescue StandardError
      false
    end

    # Check if cache store supports compression
    #
    # @param store [ActiveSupport::Cache::Store] Rails cache store
    # @return [Boolean] True if compression is supported
    def compression_support?(store)
      store.respond_to?(:options) && store.options.key?(:compress)
    rescue StandardError
      false
    end

    # Select coordination strategy based on detected capabilities
    #
    # @return [Symbol] Selected coordination strategy
    def select_coordination_strategy
      case @capabilities
      in { distributed: true, atomic_increment: true, locking: true }
        :distributed_atomic      # Redis/SolidCache with full features
      in { distributed: true, atomic_increment: true }
        :distributed_basic       # Redis/Memcached without locking
      in { distributed: true }
        :distributed_basic       # Basic distributed cache
      else
        :local_only # Memory/File store - no cross-process sync
      end
    end

    # Default capabilities for unknown or failed detection
    #
    # @return [Hash] Safe default capabilities
    def default_capabilities
      {
        distributed: false,
        atomic_increment: false,
        locking: false,
        ttl_inspection: false,
        namespace_support: false,
        compression_support: false,
        key_transformation: true,
        store_class: @store_class_name
      }
    end

    # Check if Rails.cache is available and functional
    #
    # @return [Boolean] True if Rails.cache is available
    def rails_cache_available?
      return false if @store.nil?
      defined?(Rails) && @store.respond_to?(:read) && @store.respond_to?(:write)
    rescue StandardError
      false
    end

    # Log strategy detection results
    def log_strategy_detection
      log_structured(:info, 'Cache strategy detected',
        store_class: @store_class_name,
        coordination_strategy: @coordination_mode,
        capabilities: @capabilities,
        instance_id: @instance_id
      )
    end
  end

  # Singleton registry for managing custom detectors and caching strategies
  class DetectorRegistry
    include Singleton

    def initialize
      @custom_detectors = {}
      @strategy_cache = {}
      @cache_mutex = Mutex.new
    end

    # Register a custom cache store detector
    #
    # @param pattern [Regexp, String] Pattern to match store class names
    # @param detector [Proc] Detector that returns capabilities hash
    def register_detector(pattern, detector)
      @cache_mutex.synchronize do
        @custom_detectors[pattern] = detector
        @strategy_cache.clear # Clear cache when detectors change
      end
    end

    # Clear all registered detectors (primarily for testing)
    def clear_detectors!
      @cache_mutex.synchronize do
        @custom_detectors.clear
        @strategy_cache.clear
      end
    end

    # Get custom detectors (thread-safe read access)
    def custom_detectors
      @cache_mutex.synchronize { @custom_detectors.dup }
    end

    # Cache strategy instances for performance
    def cached_strategy_for(store_class_name)
      @cache_mutex.synchronize do
        @strategy_cache[store_class_name]
      end
    end

    def cache_strategy_for(store_class_name, strategy_instance)
      @cache_mutex.synchronize do
        @strategy_cache[store_class_name] = strategy_instance
      end
    end
  end
end
