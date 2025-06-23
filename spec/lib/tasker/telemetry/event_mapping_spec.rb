# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Telemetry::EventMapping, type: :model do
  describe '.new' do
    it 'creates a mapping with required attributes' do
      mapping = described_class.new(
        event_name: 'task.completed',
        backends: %i[trace metrics]
      )

      expect(mapping.event_name).to eq('task.completed')
      expect(mapping.backends).to eq(%i[trace metrics])
      expect(mapping.enabled).to be(true)
      expect(mapping.sampling_rate).to eq(1.0)
      expect(mapping.priority).to eq(:normal)
      expect(mapping.metadata).to eq({})
    end

    it 'accepts optional attributes' do
      mapping = described_class.new(
        event_name: 'step.before_handle',
        backends: [:trace],
        enabled: false,
        sampling_rate: 0.1,
        priority: :high,
        metadata: { source: 'test' }
      )

      expect(mapping.event_name).to eq('step.before_handle')
      expect(mapping.backends).to eq([:trace])
      expect(mapping.enabled).to be(false)
      expect(mapping.sampling_rate).to eq(0.1)
      expect(mapping.priority).to eq(:high)
      expect(mapping.metadata).to eq({ source: 'test' })
    end

    it 'transforms keys to symbols' do
      mapping = described_class.new(
        'event_name' => 'task.failed',
        'backends' => [:metrics],
        'enabled' => true
      )

      expect(mapping.event_name).to eq('task.failed')
      expect(mapping.backends).to eq([:metrics])
      expect(mapping.enabled).to be(true)
    end

    it 'is immutable after creation' do
      mapping = described_class.new(event_name: 'test.event', backends: [:trace])

      expect(mapping).to be_frozen
      expect { mapping.backends << :metrics }.to raise_error(FrozenError)
    end
  end

  describe '#routes_to_traces?' do
    it 'returns true when backends includes :trace' do
      mapping = described_class.new(
        event_name: 'task.completed',
        backends: %i[trace metrics]
      )

      expect(mapping.routes_to_traces?).to be(true)
    end

    it 'returns false when backends does not include :trace' do
      mapping = described_class.new(
        event_name: 'task.completed',
        backends: [:metrics]
      )

      expect(mapping.routes_to_traces?).to be(false)
    end
  end

  describe '#routes_to_metrics?' do
    it 'returns true when backends includes :metrics' do
      mapping = described_class.new(
        event_name: 'task.completed',
        backends: %i[trace metrics]
      )

      expect(mapping.routes_to_metrics?).to be(true)
    end

    it 'returns false when backends does not include :metrics' do
      mapping = described_class.new(
        event_name: 'task.completed',
        backends: [:trace]
      )

      expect(mapping.routes_to_metrics?).to be(false)
    end
  end

  describe '#routes_to_logs?' do
    it 'returns true when backends includes :logs' do
      mapping = described_class.new(
        event_name: 'task.completed',
        backends: %i[trace logs]
      )

      expect(mapping.routes_to_logs?).to be(true)
    end

    it 'returns false when backends does not include :logs' do
      mapping = described_class.new(
        event_name: 'task.completed',
        backends: [:trace]
      )

      expect(mapping.routes_to_logs?).to be(false)
    end
  end

  describe '#should_sample?' do
    it 'returns true for sampling_rate >= 1.0' do
      mapping = described_class.new(
        event_name: 'test.event',
        backends: [:trace],
        sampling_rate: 1.0
      )

      expect(mapping.should_sample?).to be(true)
    end

    it 'returns false for sampling_rate <= 0.0' do
      mapping = described_class.new(
        event_name: 'test.event',
        backends: [:trace],
        sampling_rate: 0.0
      )

      expect(mapping.should_sample?).to be(false)
    end

    it 'returns probabilistic result for 0.0 < sampling_rate < 1.0' do
      mapping = described_class.new(
        event_name: 'test.event',
        backends: [:trace],
        sampling_rate: 0.5
      )

      # Test multiple times to verify probabilistic behavior
      results = Array.new(100) { mapping.should_sample? }

      # Should have both true and false results
      expect(results).to include(true)
      expect(results).to include(false)

      # Should be roughly 50% (allow for variance in random sampling)
      true_count = results.count(true)
      expect(true_count).to be_between(30, 70)
    end
  end

  describe '#active?' do
    it 'returns true when enabled and should_sample? is true' do
      mapping = described_class.new(
        event_name: 'test.event',
        backends: [:trace],
        enabled: true,
        sampling_rate: 1.0
      )

      expect(mapping.active?).to be(true)
    end

    it 'returns false when disabled' do
      mapping = described_class.new(
        event_name: 'test.event',
        backends: [:trace],
        enabled: false,
        sampling_rate: 1.0
      )

      expect(mapping.active?).to be(false)
    end

    it 'returns false when sampling rate is 0' do
      mapping = described_class.new(
        event_name: 'test.event',
        backends: [:trace],
        enabled: true,
        sampling_rate: 0.0
      )

      expect(mapping.active?).to be(false)
    end
  end

  describe '#description' do
    it 'returns a human-readable description' do
      mapping = described_class.new(
        event_name: 'task.completed',
        backends: %i[trace metrics],
        sampling_rate: 0.75
      )

      expected = 'task.completed → trace, metrics (75.0% sampled)'
      expect(mapping.description).to eq(expected)
    end

    it 'handles single backend' do
      mapping = described_class.new(
        event_name: 'step.failed',
        backends: [:metrics],
        sampling_rate: 1.0
      )

      expected = 'step.failed → metrics (100.0% sampled)'
      expect(mapping.description).to eq(expected)
    end

    it 'handles fractional sampling rates' do
      mapping = described_class.new(
        event_name: 'debug.event',
        backends: [:trace],
        sampling_rate: 0.1
      )

      expected = 'debug.event → trace (10.0% sampled)'
      expect(mapping.description).to eq(expected)
    end
  end

  describe 'integration with BaseConfig' do
    it 'inherits immutability from BaseConfig' do
      mapping = described_class.new(
        event_name: 'test.event',
        backends: [:trace]
      )

      expect(mapping).to be_frozen
    end

    it 'inherits key transformation from BaseConfig' do
      mapping = described_class.new(
        'event_name' => 'test.event',
        'backends' => [:trace],
        'priority' => :high
      )

      expect(mapping.event_name).to eq('test.event')
      expect(mapping.backends).to eq([:trace])
      expect(mapping.priority).to eq(:high)
    end
  end

  describe 'validation scenarios' do
    it 'accepts all valid backend types' do
      mapping = described_class.new(
        event_name: 'test.event',
        backends: %i[trace metrics logs]
      )

      expect(mapping.routes_to_traces?).to be(true)
      expect(mapping.routes_to_metrics?).to be(true)
      expect(mapping.routes_to_logs?).to be(true)
    end

    it 'accepts all valid priority levels' do
      %i[low normal high critical].each do |priority|
        mapping = described_class.new(
          event_name: 'test.event',
          backends: [:trace],
          priority: priority
        )

        expect(mapping.priority).to eq(priority)
      end
    end

    it 'accepts valid sampling rates' do
      [0.0, 0.1, 0.5, 0.9, 1.0].each do |rate|
        mapping = described_class.new(
          event_name: 'test.event',
          backends: [:trace],
          sampling_rate: rate
        )

        expect(mapping.sampling_rate).to eq(rate)
      end
    end
  end
end
