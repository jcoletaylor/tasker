# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Types::CacheConfig do
  describe 'initialization' do
    it 'creates a valid config with default values' do
      config = described_class.new

      expect(config.default_ttl).to eq(300)
      expect(config.adaptive_ttl_enabled).to be(true)
      expect(config.performance_tracking_enabled).to be(true)
      expect(config.hit_rate_smoothing_factor).to eq(0.9)
      expect(config.access_frequency_decay_rate).to eq(0.95)
      expect(config.min_adaptive_ttl).to eq(30)
      expect(config.max_adaptive_ttl).to eq(3600)
      expect(config.dashboard_cache_ttl).to eq(120)
      expect(config.cache_pressure_threshold).to eq(0.8)
      expect(config.adaptive_calculation_interval).to eq(30)
    end

    it 'accepts custom configuration values' do
      config = described_class.new(
        default_ttl: 600,
        adaptive_ttl_enabled: false,
        performance_tracking_enabled: false,
        hit_rate_smoothing_factor: 0.95,
        access_frequency_decay_rate: 0.98,
        min_adaptive_ttl: 60,
        max_adaptive_ttl: 7200,
        dashboard_cache_ttl: 180,
        cache_pressure_threshold: 0.9,
        adaptive_calculation_interval: 15
      )

      expect(config.default_ttl).to eq(600)
      expect(config.adaptive_ttl_enabled).to be(false)
      expect(config.performance_tracking_enabled).to be(false)
      expect(config.hit_rate_smoothing_factor).to eq(0.95)
      expect(config.access_frequency_decay_rate).to eq(0.98)
      expect(config.min_adaptive_ttl).to eq(60)
      expect(config.max_adaptive_ttl).to eq(7200)
      expect(config.dashboard_cache_ttl).to eq(180)
      expect(config.cache_pressure_threshold).to eq(0.9)
      expect(config.adaptive_calculation_interval).to eq(15)
    end

    it 'transforms string keys to symbols' do
      config = described_class.new(
        'default_ttl' => 600,
        'adaptive_ttl_enabled' => false
      )

      expect(config.default_ttl).to eq(600)
      expect(config.adaptive_ttl_enabled).to be(false)
    end

    it 'is frozen after initialization' do
      config = described_class.new

      expect(config).to be_frozen
    end
  end

  describe 'TTL validation' do
    describe '#validate_ttl_configuration' do
      it 'returns no errors for valid TTL configuration' do
        config = described_class.new

        errors = config.validate_ttl_configuration

        expect(errors).to be_empty
      end

      it 'validates default_ttl is positive' do
        config = described_class.new(default_ttl: 0)

        errors = config.validate_ttl_configuration

        expect(errors).to include('default_ttl must be positive (got: 0)')
      end

      it 'validates min_adaptive_ttl is positive' do
        config = described_class.new(min_adaptive_ttl: -10)

        errors = config.validate_ttl_configuration

        expect(errors).to include('min_adaptive_ttl must be positive (got: -10)')
      end

      it 'validates max_adaptive_ttl is positive' do
        config = described_class.new(max_adaptive_ttl: 0)

        errors = config.validate_ttl_configuration

        expect(errors).to include('max_adaptive_ttl must be positive (got: 0)')
      end

      it 'validates min_adaptive_ttl is less than max_adaptive_ttl' do
        config = described_class.new(
          min_adaptive_ttl: 3600,
          max_adaptive_ttl: 1800
        )

        errors = config.validate_ttl_configuration

        expect(errors).to include('min_adaptive_ttl (3600) must be less than max_adaptive_ttl (1800)')
      end

      it 'validates dashboard_cache_ttl is positive' do
        config = described_class.new(dashboard_cache_ttl: -5)

        errors = config.validate_ttl_configuration

        expect(errors).to include('dashboard_cache_ttl must be positive (got: -5)')
      end
    end
  end

  describe 'algorithm parameter validation' do
    describe '#validate_algorithm_parameters' do
      it 'returns no errors for valid algorithm parameters' do
        config = described_class.new

        errors = config.validate_algorithm_parameters

        expect(errors).to be_empty
      end

      it 'validates hit_rate_smoothing_factor is between 0.0 and 1.0' do
        config = described_class.new(hit_rate_smoothing_factor: 1.5)

        errors = config.validate_algorithm_parameters

        expect(errors).to include('hit_rate_smoothing_factor must be between 0.0 and 1.0 (got: 1.5)')
      end

      it 'validates access_frequency_decay_rate is between 0.0 and 1.0' do
        config = described_class.new(access_frequency_decay_rate: -0.1)

        errors = config.validate_algorithm_parameters

        expect(errors).to include('access_frequency_decay_rate must be between 0.0 and 1.0 (got: -0.1)')
      end

      it 'validates cache_pressure_threshold is between 0.0 and 1.0' do
        config = described_class.new(cache_pressure_threshold: 2.0)

        errors = config.validate_algorithm_parameters

        expect(errors).to include('cache_pressure_threshold must be between 0.0 and 1.0 (got: 2.0)')
      end

      it 'validates adaptive_calculation_interval is positive' do
        config = described_class.new(adaptive_calculation_interval: 0)

        errors = config.validate_algorithm_parameters

        expect(errors).to include('adaptive_calculation_interval must be positive (got: 0)')
      end
    end
  end

  describe '#validate!' do
    it 'does not raise for valid configuration' do
      config = described_class.new

      expect { config.validate! }.not_to raise_error
    end

    it 'raises ArgumentError with all validation errors' do
      config = described_class.new(
        default_ttl: -100,
        hit_rate_smoothing_factor: 1.5,
        min_adaptive_ttl: 3600,
        max_adaptive_ttl: 1800
      )

      expect { config.validate! }.to raise_error(
        ArgumentError,
        /Invalid cache configuration:.*default_ttl must be positive.*min_adaptive_ttl.*must be less than.*hit_rate_smoothing_factor must be between/
      )
    end
  end

  describe '#calculate_adaptive_ttl' do
    context 'when adaptive TTL is disabled' do
      it 'returns the base TTL unchanged' do
        config = described_class.new(adaptive_ttl_enabled: false)

        result = config.calculate_adaptive_ttl(300)

        expect(result).to eq(300)
      end
    end

    context 'when adaptive TTL is enabled' do
      let(:config) { described_class.new(min_adaptive_ttl: 60, max_adaptive_ttl: 1800) }

      it 'increases TTL for high hit rate' do
        result = config.calculate_adaptive_ttl(300, hit_rate: 0.9)

        expect(result).to be > 300
        expect(result).to eq(450) # 300 * 1.5
      end

      it 'decreases TTL for low hit rate' do
        result = config.calculate_adaptive_ttl(300, hit_rate: 0.2)

        expect(result).to be < 300
        expect(result).to eq(210) # 300 * 0.7
      end

      it 'increases TTL for expensive generation' do
        result = config.calculate_adaptive_ttl(300, generation_time: 2.0)

        expect(result).to be > 300
        expect(result).to eq(390) # 300 * 1.3
      end

      it 'decreases TTL for cheap generation' do
        result = config.calculate_adaptive_ttl(300, generation_time: 0.05)

        expect(result).to be < 300
        expect(result).to eq(240) # 300 * 0.8
      end

      it 'increases TTL for high access frequency' do
        result = config.calculate_adaptive_ttl(300, access_frequency: 150)

        expect(result).to be > 300
        expect(result).to eq(360) # 300 * 1.2
      end

      it 'decreases TTL for low access frequency' do
        result = config.calculate_adaptive_ttl(300, access_frequency: 3)

        expect(result).to be < 300
        expect(result).to eq(270) # 300 * 0.9
      end

      it 'applies multiple adjustments cumulatively' do
        result = config.calculate_adaptive_ttl(
          300,
          hit_rate: 0.9,         # * 1.5 = 450
          generation_time: 2.0,  # * 1.3 = 585
          access_frequency: 150  # * 1.2 = 702
        )

        expect(result).to eq(702)
      end

      it 'respects minimum TTL bounds' do
        config = described_class.new(min_adaptive_ttl: 100, max_adaptive_ttl: 1800)

        result = config.calculate_adaptive_ttl(
          120,
          hit_rate: 0.2,        # * 0.7 = 84
          generation_time: 0.05, # * 0.8 = 67.2
          access_frequency: 3    # * 0.9 = 60.48
        )

        expect(result).to eq(100) # Clamped to minimum
      end

      it 'respects maximum TTL bounds' do
        config = described_class.new(min_adaptive_ttl: 60, max_adaptive_ttl: 1000)

        result = config.calculate_adaptive_ttl(
          800,
          hit_rate: 0.9,         # * 1.5 = 1200
          generation_time: 2.0,  # * 1.3 = 1560
          access_frequency: 150  # * 1.2 = 1872
        )

        expect(result).to eq(1000) # Clamped to maximum
      end
    end
  end

  describe '#cache_under_pressure?' do
    it 'returns false when utilization is below threshold' do
      config = described_class.new(cache_pressure_threshold: 0.8)

      expect(config.cache_under_pressure?(0.7)).to be(false)
    end

    it 'returns true when utilization equals threshold' do
      config = described_class.new(cache_pressure_threshold: 0.8)

      expect(config.cache_under_pressure?(0.8)).to be(true)
    end

    it 'returns true when utilization exceeds threshold' do
      config = described_class.new(cache_pressure_threshold: 0.8)

      expect(config.cache_under_pressure?(0.9)).to be(true)
    end
  end

  describe 'environment-specific configurations' do
    it 'supports development environment configuration' do
      config = described_class.new(
        default_ttl: 120,
        adaptive_ttl_enabled: false,
        performance_tracking_enabled: false
      )

      expect(config.default_ttl).to eq(120)
      expect(config.adaptive_ttl_enabled).to be(false)
      expect(config.performance_tracking_enabled).to be(false)
    end

    it 'supports production environment configuration' do
      config = described_class.new(
        default_ttl: 300,
        hit_rate_smoothing_factor: 0.95,
        access_frequency_decay_rate: 0.98,
        adaptive_ttl_enabled: true,
        performance_tracking_enabled: true
      )

      expect(config.default_ttl).to eq(300)
      expect(config.hit_rate_smoothing_factor).to eq(0.95)
      expect(config.access_frequency_decay_rate).to eq(0.98)
      expect(config.adaptive_ttl_enabled).to be(true)
      expect(config.performance_tracking_enabled).to be(true)
    end

    it 'supports high-performance environment configuration' do
      config = described_class.new(
        default_ttl: 600,
        min_adaptive_ttl: 60,
        max_adaptive_ttl: 7200,
        cache_pressure_threshold: 0.9,
        adaptive_calculation_interval: 15
      )

      expect(config.default_ttl).to eq(600)
      expect(config.min_adaptive_ttl).to eq(60)
      expect(config.max_adaptive_ttl).to eq(7200)
      expect(config.cache_pressure_threshold).to eq(0.9)
      expect(config.adaptive_calculation_interval).to eq(15)
    end
  end
end
