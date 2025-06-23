# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Telemetry::MetricTypes do
  describe 'Counter' do
    subject(:counter) { described_class::Counter.new('test_counter', labels: { env: 'test' }) }

    describe '#initialize' do
      it 'creates a counter with name and labels' do
        expect(counter.name).to eq('test_counter')
        expect(counter.labels).to eq({ env: 'test' })
        expect(counter.value).to eq(0)
        expect(counter.created_at).to be_a(Time)
      end

      it 'requires a non-empty name' do
        expect { described_class::Counter.new(nil) }.to raise_error(ArgumentError, /name cannot be nil or empty/)
        expect { described_class::Counter.new('') }.to raise_error(ArgumentError, /name cannot be nil or empty/)
        expect { described_class::Counter.new('   ') }.to raise_error(ArgumentError, /name cannot be nil or empty/)
      end

      it 'freezes name and labels for immutability' do
        expect(counter.name).to be_frozen
        expect(counter.labels).to be_frozen
        expect(counter.created_at).to be_frozen
      end

      it 'handles empty labels' do
        simple_counter = described_class::Counter.new('simple')
        expect(simple_counter.labels).to eq({})
        expect(simple_counter.labels).to be_frozen
      end
    end

    describe '#increment' do
      it 'increments by 1 by default' do
        expect { counter.increment }.to change { counter.value }.from(0).to(1)
      end

      it 'increments by specified amount' do
        expect { counter.increment(5) }.to change { counter.value }.from(0).to(5)
        expect { counter.increment(3) }.to change { counter.value }.from(5).to(8)
      end

      it 'returns the new value' do
        result = counter.increment(10)
        expect(result).to eq(10)
      end

      it 'requires non-negative integer amounts' do
        expect { counter.increment(-1) }.to raise_error(ArgumentError, /must be positive/)
        expect { counter.increment(0) }.not_to raise_error  # Zero increment is allowed
      end

      it 'requires integer amounts' do
        expect(counter.increment('invalid')).to eq(false)
        expect(counter.increment(1.5)).to eq(false)
        expect(counter.increment(nil)).to eq(false)
      end

      it 'is thread-safe' do
        threads = []
        increment_count = 1000

        10.times do
          threads << Thread.new do
            increment_count.times { counter.increment }
          end
        end

        threads.each(&:join)
        expect(counter.value).to eq(10 * increment_count)
      end
    end

    describe '#reset!' do
      it 'resets counter to zero' do
        counter.increment(42)
        expect { counter.reset! }.to change { counter.value }.from(42).to(0)
      end
    end

    describe '#to_h' do
      before { counter.increment(15) }

      it 'returns comprehensive hash representation' do
        hash = counter.to_h
        expect(hash).to include(
          name: 'test_counter',
          labels: { env: 'test' },
          value: 15,
          type: :counter,
          created_at: counter.created_at
        )
        expect(hash.keys).to match_array(%i[name labels value type created_at])
      end
    end

    describe '#description' do
      before { counter.increment(7) }

      it 'provides human-readable description' do
        expect(counter.description).to eq('test_counter{:env=>"test"} = 7 (counter)')
      end

      it 'handles empty labels gracefully' do
        simple_counter = described_class::Counter.new('simple')
        simple_counter.increment(3)
        expect(simple_counter.description).to eq('simple = 3 (counter)')
      end
    end
  end

  describe 'Gauge' do
    subject(:gauge) { described_class::Gauge.new('test_gauge', labels: { service: 'api' }) }

    describe '#initialize' do
      it 'creates a gauge with name, labels, and initial value' do
        expect(gauge.name).to eq('test_gauge')
        expect(gauge.labels).to eq({ service: 'api' })
        expect(gauge.value).to eq(0)
        expect(gauge.created_at).to be_a(Time)
      end

      it 'accepts custom initial value' do
        custom_gauge = described_class::Gauge.new('custom', initial_value: 42.5)
        expect(custom_gauge.value).to eq(42.5)
      end

      it 'requires numeric initial value' do
        expect { described_class::Gauge.new('invalid', initial_value: 'string') }
          .to raise_error(ArgumentError, /must be numeric/)
      end

      it 'requires non-empty name' do
        expect { described_class::Gauge.new(nil) }.to raise_error(ArgumentError, /name cannot be nil or empty/)
      end

      it 'freezes immutable attributes' do
        expect(gauge.name).to be_frozen
        expect(gauge.labels).to be_frozen
        expect(gauge.created_at).to be_frozen
      end
    end

    describe '#set' do
      it 'sets gauge to specific value' do
        expect { gauge.set(100.5) }.to change { gauge.value }.from(0).to(100.5)
      end

      it 'returns the new value' do
        result = gauge.set(42)
        expect(result).to eq(42)
      end

      it 'requires numeric values' do
        expect { gauge.set('invalid') }.to raise_error(ArgumentError, /must be numeric/)
        expect { gauge.set(nil) }.to raise_error(ArgumentError, /must be numeric/)
      end

      it 'handles negative values' do
        expect { gauge.set(-50) }.to change { gauge.value }.to(-50)
      end

      it 'is thread-safe' do
        threads = []
        values = (1..100).to_a

        values.each do |value|
          threads << Thread.new { gauge.set(value) }
        end

        threads.each(&:join)
        expect(values).to include(gauge.value)
      end
    end

    describe '#increment' do
      before { gauge.set(10) }

      it 'increments by 1 by default' do
        expect { gauge.increment }.to change { gauge.value }.from(10).to(11)
      end

      it 'increments by specified amount' do
        expect { gauge.increment(5.5) }.to change { gauge.value }.from(10).to(15.5)
      end

      it 'handles negative increments' do
        expect { gauge.increment(-3) }.to change { gauge.value }.from(10).to(7)
      end

      it 'returns the new value' do
        result = gauge.increment(2.5)
        expect(result).to eq(12.5)
      end

      it 'requires numeric amounts' do
        expect { gauge.increment('invalid') }.to raise_error(ArgumentError, /must be numeric/)
      end

      it 'is thread-safe' do
        threads = []
        increment_count = 1000

        5.times do
          threads << Thread.new do
            increment_count.times { gauge.increment(0.001) }
          end
        end

        threads.each(&:join)
        expected_value = 10 + (5 * increment_count * 0.001)
        expect(gauge.value).to be_within(0.001).of(expected_value)
      end
    end

    describe '#decrement' do
      before { gauge.set(20) }

      it 'decrements by 1 by default' do
        expect { gauge.decrement }.to change { gauge.value }.from(20).to(19)
      end

      it 'decrements by specified amount' do
        expect { gauge.decrement(7.5) }.to change { gauge.value }.from(20).to(12.5)
      end

      it 'returns the new value' do
        result = gauge.decrement(3)
        expect(result).to eq(17)
      end

      it 'requires positive amounts' do
        expect { gauge.decrement(-5) }.to raise_error(ArgumentError, /must be positive/)
      end

      it 'requires numeric amounts' do
        expect { gauge.decrement('invalid') }.to raise_error(ArgumentError, /must be numeric/)
      end
    end

    describe '#to_h' do
      before { gauge.set(42.7) }

      it 'returns comprehensive hash representation' do
        hash = gauge.to_h
        expect(hash).to include(
          name: 'test_gauge',
          labels: { service: 'api' },
          value: 42.7,
          type: :gauge,
          created_at: gauge.created_at
        )
      end
    end

    describe '#description' do
      before { gauge.set(25.5) }

      it 'provides human-readable description' do
        expect(gauge.description).to eq('test_gauge{:service=>"api"} = 25.5 (gauge)')
      end
    end
  end

  describe 'Histogram' do
    subject(:histogram) { described_class::Histogram.new('test_histogram', labels: { method: 'POST' }) }

    describe '#initialize' do
      it 'creates histogram with default buckets' do
        expect(histogram.name).to eq('test_histogram')
        expect(histogram.labels).to eq({ method: 'POST' })
        expect(histogram.bucket_boundaries).to eq(described_class::Histogram::DEFAULT_BUCKETS)
        expect(histogram.count).to eq(0)
        expect(histogram.sum).to eq(0.0)
      end

      it 'accepts custom buckets' do
        custom_histogram = described_class::Histogram.new('custom', buckets: [0.1, 0.5, 1.0])
        expect(custom_histogram.bucket_boundaries).to eq([0.1, 0.5, 1.0])
      end

      it 'requires non-empty name' do
        expect { described_class::Histogram.new(nil) }.to raise_error(ArgumentError, /name cannot be nil or empty/)
      end

      it 'requires valid buckets' do
        expect { described_class::Histogram.new('test', buckets: []) }
          .to raise_error(ArgumentError, /cannot be empty/)

        expect { described_class::Histogram.new('test', buckets: 'invalid') }
          .to raise_error(ArgumentError, /must be an array/)

        # Auto-sorting behavior - unsorted buckets should be automatically sorted
        histogram = described_class::Histogram.new('test', buckets: [1.0, 0.5])
        expect(histogram.bucket_boundaries).to eq([0.5, 1.0])
      end

      it 'sorts buckets automatically' do
        histogram = described_class::Histogram.new('sorted', buckets: [5.0, 1.0, 2.5])
        expect(histogram.bucket_boundaries).to eq([1.0, 2.5, 5.0])
      end

      it 'freezes immutable attributes' do
        expect(histogram.name).to be_frozen
        expect(histogram.labels).to be_frozen
        expect(histogram.bucket_boundaries).to be_frozen
        expect(histogram.created_at).to be_frozen
      end
    end

    describe '#observe' do
      it 'records observations and updates statistics' do
        expect { histogram.observe(0.5) }.to change { histogram.count }.from(0).to(1)
        expect(histogram.sum).to eq(0.5)
      end

      it 'returns the observed value' do
        result = histogram.observe(1.5)
        expect(result).to eq(1.5)
      end

      it 'updates bucket counts correctly' do
        histogram.observe(0.003)  # Should be in first bucket (0.005)
        histogram.observe(0.5)    # Should be in 0.5 bucket
        histogram.observe(15.0)   # Should be in infinity bucket

        buckets = histogram.buckets
        expect(buckets[0.005]).to eq(1)      # First observation
        expect(buckets[0.5]).to eq(2)        # First + second observations
        expect(buckets[Float::INFINITY]).to eq(3) # All observations
      end

      it 'calculates average correctly' do
        histogram.observe(1.0)
        histogram.observe(3.0)
        histogram.observe(2.0)

        expect(histogram.count).to eq(3)
        expect(histogram.sum).to eq(6.0)
        expect(histogram.average).to eq(2.0)
      end

      it 'handles zero observations gracefully' do
        expect(histogram.average).to eq(0.0)
      end

      it 'requires numeric values' do
        expect { histogram.observe('invalid') }.to raise_error(ArgumentError, /must be numeric/)
        expect { histogram.observe(nil) }.to raise_error(ArgumentError, /must be numeric/)
      end

      it 'handles negative values' do
        expect { histogram.observe(-1.0) }.not_to raise_error
        expect(histogram.sum).to eq(-1.0)
      end

      it 'is thread-safe' do
        threads = []
        observations_per_thread = 1000

        5.times do |i|
          threads << Thread.new do
            observations_per_thread.times do
              histogram.observe(i * 0.1)
            end
          end
        end

        threads.each(&:join)
        expect(histogram.count).to eq(5 * observations_per_thread)

        # Check that all bucket counts are consistent
        total_count = histogram.buckets[Float::INFINITY]
        expect(total_count).to eq(5 * observations_per_thread)
      end
    end

    describe '#buckets' do
      before do
        histogram.observe(0.003)
        histogram.observe(0.5)
        histogram.observe(15.0)
      end

      it 'returns bucket counts' do
        buckets = histogram.buckets
        expect(buckets).to be_a(Hash)
        expect(buckets.keys).to include(0.005, 0.5, Float::INFINITY)
        expect(buckets[Float::INFINITY]).to eq(3)
      end

      it 'includes all bucket boundaries' do
        bucket_keys = histogram.buckets.keys
        described_class::Histogram::DEFAULT_BUCKETS.each do |boundary|
          expect(bucket_keys).to include(boundary)
        end
        expect(bucket_keys).to include(Float::INFINITY)
      end
    end

    describe '#reset!' do
      before do
        histogram.observe(1.0)
        histogram.observe(2.0)
      end

      it 'resets all statistics' do
        expect { histogram.reset! }.to change { histogram.count }.from(2).to(0)
        expect(histogram.sum).to eq(0.0)
        expect(histogram.average).to eq(0.0)
        expect(histogram.buckets.values.sum).to eq(0)
      end
    end

    describe '#to_h' do
      before do
        histogram.observe(1.5)
        histogram.observe(2.5)
      end

      it 'returns comprehensive hash representation' do
        hash = histogram.to_h
        expect(hash).to include(
          name: 'test_histogram',
          labels: { method: 'POST' },
          count: 2,
          sum: 4.0,
          average: 2.0,
          type: :histogram,
          created_at: histogram.created_at
        )
        expect(hash[:buckets]).to be_a(Hash)
      end
    end

    describe '#description' do
      before do
        histogram.observe(1.0)
        histogram.observe(2.0)
        histogram.observe(3.0)
      end

      it 'provides human-readable description' do
        expected = 'test_histogram{:method=>"POST"} = 3 observations, avg: 2.0 (histogram)'
        expect(histogram.description).to eq(expected)
      end

      it 'handles empty labels gracefully' do
        simple_histogram = described_class::Histogram.new('simple')
        simple_histogram.observe(5.0)
        expect(simple_histogram.description).to eq('simple = 1 observations, avg: 5.0 (histogram)')
      end
    end
  end

  describe 'Performance characteristics' do
    let(:counter) { described_class::Counter.new('perf_counter') }
    let(:gauge) { described_class::Gauge.new('perf_Gauge') }
    let(:histogram) { described_class::Histogram.new('perf_histogram') }

    it 'performs counter operations efficiently' do
      expect {
        10_000.times { counter.increment }
      }.to take_less_than(0.1)
    end

    it 'performs gauge operations efficiently' do
      expect {
        10_000.times { |i| gauge.set(i) }
      }.to take_less_than(0.1)
    end

    it 'performs histogram observations efficiently' do
      expect {
        10_000.times { |i| histogram.observe(i * 0.001) }
      }.to take_less_than(0.5)  # Histograms are more complex
    end
  end
end

# Custom RSpec matcher for timing assertions
RSpec::Matchers.define :take_less_than do |expected_duration|
  supports_block_expectations

  match do |block|
    start_time = Time.current
    block.call
    end_time = Time.current
    @actual_duration = end_time - start_time
    @actual_duration < expected_duration
  end

  failure_message do
    "expected block to take less than #{expected_duration} seconds, but took #{@actual_duration.round(4)} seconds"
  end
end
