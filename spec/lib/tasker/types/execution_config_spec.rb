# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Types::ExecutionConfig do
  describe 'default configuration' do
    let(:config) { described_class.new }

    it 'provides sensible defaults for all configurable settings' do
      expect(config.min_concurrent_steps).to eq(3)
      expect(config.max_concurrent_steps_limit).to eq(12)
      expect(config.concurrency_cache_duration).to eq(30)
      expect(config.batch_timeout_base_seconds).to eq(30)
      expect(config.batch_timeout_per_step_seconds).to eq(5)
      expect(config.max_batch_timeout_seconds).to eq(120)
    end

    it 'provides correct architectural constants' do
      expect(config.future_cleanup_wait_seconds).to eq(1)
      expect(config.gc_trigger_batch_size_threshold).to eq(6)
      expect(config.gc_trigger_duration_threshold).to eq(30)
    end
  end

  describe 'custom configuration' do
    let(:config) do
      described_class.new(
        min_concurrent_steps: 5,
        max_concurrent_steps_limit: 25,
        concurrency_cache_duration: 60,
        batch_timeout_base_seconds: 45,
        batch_timeout_per_step_seconds: 10,
        max_batch_timeout_seconds: 300
      )
    end

    it 'accepts custom values for configurable settings' do
      expect(config.min_concurrent_steps).to eq(5)
      expect(config.max_concurrent_steps_limit).to eq(25)
      expect(config.concurrency_cache_duration).to eq(60)
      expect(config.batch_timeout_base_seconds).to eq(45)
      expect(config.batch_timeout_per_step_seconds).to eq(10)
      expect(config.max_batch_timeout_seconds).to eq(300)
    end

    it 'maintains architectural constants regardless of custom configuration' do
      expect(config.future_cleanup_wait_seconds).to eq(1)
      expect(config.gc_trigger_batch_size_threshold).to eq(6)
      expect(config.gc_trigger_duration_threshold).to eq(30)
    end
  end

  describe '#calculate_batch_timeout' do
    let(:config) { described_class.new }

    it 'calculates timeout based on batch size' do
      expect(config.calculate_batch_timeout(1)).to eq(35) # 30 + (1 * 5)
      expect(config.calculate_batch_timeout(5)).to eq(55) # 30 + (5 * 5)
      expect(config.calculate_batch_timeout(10)).to eq(80) # 30 + (10 * 5)
    end

    it 'respects maximum timeout cap' do
      expect(config.calculate_batch_timeout(100)).to eq(120) # Capped at max_batch_timeout_seconds
    end

    context 'with custom timeout settings' do
      let(:config) do
        described_class.new(
          batch_timeout_base_seconds: 60,
          batch_timeout_per_step_seconds: 10,
          max_batch_timeout_seconds: 300
        )
      end

      it 'uses custom settings for calculation' do
        expect(config.calculate_batch_timeout(5)).to eq(110) # 60 + (5 * 10)
        expect(config.calculate_batch_timeout(50)).to eq(300) # Capped at 300
      end
    end
  end

  describe '#should_trigger_gc?' do
    let(:config) { described_class.new }

    it 'triggers GC for large batches' do
      expect(config.should_trigger_gc?(6, 10)).to be true
      expect(config.should_trigger_gc?(10, 10)).to be true
    end

    it 'triggers GC for long-running batches' do
      expect(config.should_trigger_gc?(3, 30)).to be true
      expect(config.should_trigger_gc?(3, 45)).to be true
    end

    it 'does not trigger GC for small, fast batches' do
      expect(config.should_trigger_gc?(3, 15)).to be false
      expect(config.should_trigger_gc?(5, 20)).to be false
    end
  end

  describe 'validation' do
    describe '#validate_concurrency_bounds' do
      it 'returns no errors for valid configuration' do
        config = described_class.new(min_concurrent_steps: 3, max_concurrent_steps_limit: 12)
        expect(config.validate_concurrency_bounds).to be_empty
      end

      it 'returns error for non-positive min_concurrent_steps' do
        config = described_class.new(min_concurrent_steps: 0)
        errors = config.validate_concurrency_bounds
        expect(errors).to include('min_concurrent_steps must be positive (got: 0)')
      end

      it 'returns error for non-positive max_concurrent_steps_limit' do
        config = described_class.new(max_concurrent_steps_limit: 0)
        errors = config.validate_concurrency_bounds
        expect(errors).to include('max_concurrent_steps_limit must be positive (got: 0)')
      end

      it 'returns error when min exceeds max' do
        config = described_class.new(min_concurrent_steps: 15, max_concurrent_steps_limit: 10)
        errors = config.validate_concurrency_bounds
        expect(errors).to include('min_concurrent_steps (15) cannot exceed max_concurrent_steps_limit (10)')
      end
    end

    describe '#validate_timeout_configuration' do
      it 'returns no errors for valid timeout configuration' do
        config = described_class.new
        expect(config.validate_timeout_configuration).to be_empty
      end

      it 'returns error for non-positive batch_timeout_base_seconds' do
        config = described_class.new(batch_timeout_base_seconds: 0)
        errors = config.validate_timeout_configuration
        expect(errors).to include('batch_timeout_base_seconds must be positive (got: 0)')
      end

      it 'returns error for non-positive batch_timeout_per_step_seconds' do
        config = described_class.new(batch_timeout_per_step_seconds: 0)
        errors = config.validate_timeout_configuration
        expect(errors).to include('batch_timeout_per_step_seconds must be positive (got: 0)')
      end

      it 'returns error when max timeout is not greater than base timeout' do
        config = described_class.new(
          batch_timeout_base_seconds: 60,
          max_batch_timeout_seconds: 50
        )
        errors = config.validate_timeout_configuration
        expect(errors).to include('max_batch_timeout_seconds (50) must be greater than batch_timeout_base_seconds (60)')
      end
    end

    describe '#validate!' do
      it 'passes for valid configuration' do
        config = described_class.new
        expect { config.validate! }.not_to raise_error
        expect(config.validate!).to be true
      end

      it 'raises error for invalid configuration' do
        config = described_class.new(min_concurrent_steps: 0, batch_timeout_base_seconds: 0)
        expect { config.validate! }.to raise_error(Dry::Struct::Error, /validation failed/)
      end
    end
  end

  describe 'immutability' do
    let(:config) { described_class.new }

    it 'is frozen after creation' do
      expect(config).to be_frozen
    end

    it 'cannot be modified after creation' do
      expect { config.instance_variable_set(:@min_concurrent_steps, 999) }.to raise_error(FrozenError)
    end
  end

  describe 'environment-specific examples' do
    describe 'development environment configuration' do
      let(:dev_config) do
        described_class.new(
          min_concurrent_steps: 2,
          max_concurrent_steps_limit: 6,
          concurrency_cache_duration: 60,
          batch_timeout_base_seconds: 20,
          max_batch_timeout_seconds: 60
        )
      end

      it 'provides conservative settings suitable for development' do
        expect(dev_config.min_concurrent_steps).to eq(2)
        expect(dev_config.max_concurrent_steps_limit).to eq(6)
        expect(dev_config.calculate_batch_timeout(3)).to eq(35) # 20 + (3 * 5)
        expect(dev_config.calculate_batch_timeout(20)).to eq(60) # Capped at 60
      end
    end

    describe 'production environment configuration' do
      let(:prod_config) do
        described_class.new(
          min_concurrent_steps: 5,
          max_concurrent_steps_limit: 25,
          concurrency_cache_duration: 15,
          batch_timeout_base_seconds: 45,
          batch_timeout_per_step_seconds: 8,
          max_batch_timeout_seconds: 300
        )
      end

      it 'provides high-performance settings suitable for production' do
        expect(prod_config.min_concurrent_steps).to eq(5)
        expect(prod_config.max_concurrent_steps_limit).to eq(25)
        expect(prod_config.calculate_batch_timeout(10)).to eq(125) # 45 + (10 * 8)
        expect(prod_config.calculate_batch_timeout(50)).to eq(300) # Capped at 300
      end
    end
  end
end
