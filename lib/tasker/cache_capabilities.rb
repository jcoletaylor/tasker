# frozen_string_literal: true

module Tasker
  # Module for custom cache stores to declare their capabilities
  #
  # This module provides a clean, developer-friendly API for custom cache store
  # implementations to declare their capabilities explicitly. This enables the
  # CacheStrategy system to make optimal coordination decisions without relying
  # on runtime introspection.
  #
  # **Usage Patterns**:
  # 1. Include the module in your custom cache store class
  # 2. Use convenience methods like `supports_distributed_caching!`
  # 3. Or declare capabilities explicitly with `declare_cache_capability`
  #
  # @example Basic usage with convenience methods
  #   class MyAwesomeCacheStore < ActiveSupport::Cache::Store
  #     include Tasker::CacheCapabilities
  #
  #     supports_distributed_caching!
  #     supports_atomic_increment!
  #     supports_locking!
  #   end
  #
  # @example Advanced usage with explicit declarations
  #   class MyCustomCacheStore < ActiveSupport::Cache::Store
  #     include Tasker::CacheCapabilities
  #
  #     declare_cache_capability(:distributed, true)
  #     declare_cache_capability(:atomic_increment, true)
  #     declare_cache_capability(:locking, false)
  #     declare_cache_capability(:custom_feature, true)
  #   end
  #
  # @example Runtime capability checking
  #   store = MyAwesomeCacheStore.new
  #   store.class.declared_cache_capabilities
  #   # => { distributed: true, atomic_increment: true, locking: true }
  module CacheCapabilities
    extend ActiveSupport::Concern

    class_methods do
      # Declare a specific cache capability
      #
      # @param capability [Symbol] The capability name (e.g., :distributed, :atomic_increment)
      # @param supported [Boolean] Whether this capability is supported
      def declare_cache_capability(capability, supported)
        cache_capabilities_hash[capability] = supported
      end

      # Declare support for distributed caching
      #
      # Indicates that this cache store shares data across multiple processes/containers.
      # This enables distributed coordination strategies in IntelligentCacheManager.
      def supports_distributed_caching!
        declare_cache_capability(:distributed, true)
      end

      # Declare support for atomic increment operations
      #
      # Indicates that increment/decrement operations are truly atomic at the store level.
      # This enables more efficient performance tracking and coordination.
      def supports_atomic_increment!
        declare_cache_capability(:atomic_increment, true)
      end

      # Declare support for distributed locking
      #
      # Indicates that the cache store supports distributed locking mechanisms.
      # This enables the most sophisticated coordination strategies.
      def supports_locking!
        declare_cache_capability(:locking, true)
      end

      # Declare support for TTL inspection and management
      #
      # Indicates that the cache store supports checking and extending TTL values.
      # This enables more sophisticated adaptive TTL strategies.
      def supports_ttl_inspection!
        declare_cache_capability(:ttl_inspection, true)
      end

      # Declare support for namespace isolation
      #
      # Indicates that the cache store supports namespace-based key isolation.
      # This enables multi-tenant cache strategies.
      def supports_namespace_isolation!
        declare_cache_capability(:namespace_support, true)
      end

      # Declare support for automatic compression
      #
      # Indicates that the cache store supports automatic value compression.
      # This enables memory-efficient caching strategies.
      def supports_compression!
        declare_cache_capability(:compression_support, true)
      end

      # Get all declared cache capabilities
      #
      # @return [Hash] Hash of capability => supported mappings
      def declared_cache_capabilities
        cache_capabilities_hash.dup
      end

      # Check if a specific capability has been declared
      #
      # @param capability [Symbol] The capability to check
      # @return [Boolean, nil] True/false if declared, nil if not declared
      def declared_capability_support(capability)
        cache_capabilities_hash[capability]
      end

      # Check if any capabilities have been declared
      #
      # @return [Boolean] True if any capabilities have been explicitly declared
      def has_declared_capabilities?
        cache_capabilities_hash.any?
      end

      private

      # Internal hash for storing declared capabilities
      #
      # @return [Hash] The internal capabilities hash
      def cache_capabilities_hash
        @declared_cache_capabilities ||= {}
      end
    end
  end
end
