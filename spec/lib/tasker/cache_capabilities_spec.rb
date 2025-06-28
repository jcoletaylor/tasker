# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::CacheCapabilities do
  # Test cache store class that includes CacheCapabilities
  let(:test_cache_store_class) do
    Class.new(ActiveSupport::Cache::Store) do
      include Tasker::CacheCapabilities
    end
  end

  # Reset declared capabilities between tests
  before do
    test_cache_store_class.instance_variable_set(:@declared_cache_capabilities, nil)
  end

  describe 'class methods' do
    describe '#declare_cache_capability' do
      it 'declares a cache capability' do
        test_cache_store_class.declare_cache_capability(:distributed, true)
        test_cache_store_class.declare_cache_capability(:atomic_increment, false)

        capabilities = test_cache_store_class.declared_cache_capabilities
        expect(capabilities[:distributed]).to be(true)
        expect(capabilities[:atomic_increment]).to be(false)
      end

      it 'overwrites previously declared capabilities' do
        test_cache_store_class.declare_cache_capability(:distributed, false)
        test_cache_store_class.declare_cache_capability(:distributed, true)

        capabilities = test_cache_store_class.declared_cache_capabilities
        expect(capabilities[:distributed]).to be(true)
      end
    end

    describe 'convenience methods' do
      describe '#supports_distributed_caching!' do
        it 'declares distributed capability as true' do
          test_cache_store_class.supports_distributed_caching!

          expect(test_cache_store_class.declared_cache_capabilities[:distributed]).to be(true)
        end
      end

      describe '#supports_atomic_increment!' do
        it 'declares atomic_increment capability as true' do
          test_cache_store_class.supports_atomic_increment!

          expect(test_cache_store_class.declared_cache_capabilities[:atomic_increment]).to be(true)
        end
      end

      describe '#supports_locking!' do
        it 'declares locking capability as true' do
          test_cache_store_class.supports_locking!

          expect(test_cache_store_class.declared_cache_capabilities[:locking]).to be(true)
        end
      end

      describe '#supports_ttl_inspection!' do
        it 'declares ttl_inspection capability as true' do
          test_cache_store_class.supports_ttl_inspection!

          expect(test_cache_store_class.declared_cache_capabilities[:ttl_inspection]).to be(true)
        end
      end

      describe '#supports_namespace_isolation!' do
        it 'declares namespace_support capability as true' do
          test_cache_store_class.supports_namespace_isolation!

          expect(test_cache_store_class.declared_cache_capabilities[:namespace_support]).to be(true)
        end
      end

      describe '#supports_compression!' do
        it 'declares compression_support capability as true' do
          test_cache_store_class.supports_compression!

          expect(test_cache_store_class.declared_cache_capabilities[:compression_support]).to be(true)
        end
      end
    end

    describe '#declared_cache_capabilities' do
      it 'returns empty hash initially' do
        expect(test_cache_store_class.declared_cache_capabilities).to eq({})
      end

      it 'returns declared capabilities' do
        test_cache_store_class.declare_cache_capability(:distributed, true)
        test_cache_store_class.declare_cache_capability(:custom_feature, 'advanced')

        capabilities = test_cache_store_class.declared_cache_capabilities
        expect(capabilities).to eq({
          distributed: true,
          custom_feature: 'advanced'
        })
      end

      it 'returns a new hash instance each time' do
        test_cache_store_class.declare_cache_capability(:distributed, true)

        capabilities1 = test_cache_store_class.declared_cache_capabilities
        capabilities2 = test_cache_store_class.declared_cache_capabilities

        expect(capabilities1).not_to be(capabilities2)
        expect(capabilities1).to eq(capabilities2)
      end
    end

    describe '#declared_capability_support' do
      it 'returns nil for undeclared capabilities' do
        expect(test_cache_store_class.declared_capability_support(:distributed)).to be_nil
      end

      it 'returns declared value for declared capabilities' do
        test_cache_store_class.declare_cache_capability(:distributed, true)
        test_cache_store_class.declare_cache_capability(:atomic_increment, false)

        expect(test_cache_store_class.declared_capability_support(:distributed)).to be(true)
        expect(test_cache_store_class.declared_capability_support(:atomic_increment)).to be(false)
      end
    end

    describe '#has_declared_capabilities?' do
      it 'returns false when no capabilities declared' do
        expect(test_cache_store_class.has_declared_capabilities?).to be(false)
      end

      it 'returns true when capabilities have been declared' do
        test_cache_store_class.declare_cache_capability(:distributed, true)

        expect(test_cache_store_class.has_declared_capabilities?).to be(true)
      end
    end
  end

  describe 'integration with multiple capabilities' do
    it 'supports chaining convenience methods' do
      test_cache_store_class.supports_distributed_caching!
      test_cache_store_class.supports_atomic_increment!
      test_cache_store_class.supports_locking!

      capabilities = test_cache_store_class.declared_cache_capabilities
      expect(capabilities).to eq({
        distributed: true,
        atomic_increment: true,
        locking: true
      })
    end

    it 'supports mixing convenience methods with explicit declarations' do
      test_cache_store_class.supports_distributed_caching!
      test_cache_store_class.declare_cache_capability(:custom_feature, 'enabled')
      test_cache_store_class.supports_atomic_increment!

      capabilities = test_cache_store_class.declared_cache_capabilities
      expect(capabilities).to eq({
        distributed: true,
        custom_feature: 'enabled',
        atomic_increment: true
      })
    end
  end

  describe 'inheritance behavior' do
    let(:parent_cache_store_class) do
      Class.new(ActiveSupport::Cache::Store) do
        include Tasker::CacheCapabilities
        supports_distributed_caching!
      end
    end

    let(:child_cache_store_class) do
      Class.new(parent_cache_store_class) do
        supports_atomic_increment!
      end
    end

    it 'child classes have independent capability declarations' do
      # Parent should only have distributed capability
      expect(parent_cache_store_class.declared_cache_capabilities).to eq({
        distributed: true
      })

      # Child should only have atomic_increment capability (independent of parent)
      expect(child_cache_store_class.declared_cache_capabilities).to eq({
        atomic_increment: true
      })
    end
  end

  describe 'real-world usage example' do
    let(:awesome_cache_store_class) do
      Class.new(ActiveSupport::Cache::Store) do
        include Tasker::CacheCapabilities

        # Declare this is a distributed cache with full features
        supports_distributed_caching!
        supports_atomic_increment!
        supports_locking!
        supports_ttl_inspection!
        supports_namespace_isolation!

        # Custom capability for this store
        declare_cache_capability(:advanced_analytics, true)
        declare_cache_capability(:compression_support, false) # Override default assumption
      end
    end

    it 'provides comprehensive capability declaration' do
      capabilities = awesome_cache_store_class.declared_cache_capabilities

      expect(capabilities).to eq({
        distributed: true,
        atomic_increment: true,
        locking: true,
        ttl_inspection: true,
        namespace_support: true,
        advanced_analytics: true,
        compression_support: false
      })
    end

    it 'integrates with CacheStrategy detection' do
      # Mock Rails.cache to use our awesome cache store
      store_instance = awesome_cache_store_class.new

      # Ensure the class has a proper name for testing
      allow(awesome_cache_store_class).to receive(:name).and_return('AwesomeCacheStore')
      allow(Rails).to receive(:cache).and_return(store_instance)

      strategy = Tasker::CacheStrategy.new

      # Should detect declared capabilities
      expect(strategy.supports?(:distributed)).to be(true)
      expect(strategy.supports?(:atomic_increment)).to be(true)
      expect(strategy.supports?(:locking)).to be(true)
      expect(strategy.supports?(:advanced_analytics)).to be(true)
      expect(strategy.supports?(:compression_support)).to be(false)
    end
  end
end
