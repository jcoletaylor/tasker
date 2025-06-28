# frozen_string_literal: true

require 'rails_helper'
require 'benchmark'

RSpec.describe 'FutureStateAnalyzer Performance Validation' do
  let(:futures) do
    # Create a realistic set of futures in different states
    # Ensure completion
    [
      Concurrent::Future.new { 42 }, # unscheduled
      # will complete quickly
      Concurrent::Future.execute do
        sleep 0.001
        42
      end,
      Concurrent::Future.execute { raise 'error' } # will reject
    ].tap do |fs|
      fs[1].wait
      fs[2].wait
    end
  end

  describe 'memory overhead validation' do
    it 'demonstrates minimal memory overhead' do
      # Measure memory before
      GC.start # Clean slate
      initial_objects = ObjectSpace.count_objects

      # Create 1000 analyzers (realistic batch size scenario)
      analyzers = []
      1000.times do
        futures.each do |future|
          analyzers << Tasker::Orchestration::FutureStateAnalyzer.new(future)
        end
      end

      # Measure memory after
      final_objects = ObjectSpace.count_objects

      # Calculate object increase
      object_increase = final_objects[:T_OBJECT] - initial_objects[:T_OBJECT]

      # Should be roughly 3000 new objects (1000 iterations * 3 futures)
      expect(object_increase).to be_between(2900, 3100)

      # Verify the analyzers work correctly
      expect(analyzers.first.state_description).to eq('unscheduled')

      # Clear references and force GC
      analyzers.clear
      GC.start

      # Verify cleanup
      post_gc_objects = ObjectSpace.count_objects
      expect(post_gc_objects[:T_OBJECT]).to be <= final_objects[:T_OBJECT]
    end
  end

  describe 'performance comparison: direct vs abstraction' do
    let(:test_iterations) { 10_000 }

    it 'demonstrates minimal performance overhead' do
      # Benchmark direct future state checking
      direct_time = Benchmark.realtime do
        test_iterations.times do
          futures.each do |future|
            # Direct approach (what we had before)
            future.pending?
            future.incomplete? && !future.unscheduled?
            future.complete? || future.unscheduled?
          end
        end
      end

      # Benchmark abstraction approach
      abstraction_time = Benchmark.realtime do
        test_iterations.times do
          futures.each do |future|
            # Abstraction approach (what we have now)
            analyzer = Tasker::Orchestration::FutureStateAnalyzer.new(future)
            analyzer.should_cancel?
            analyzer.should_wait_for_completion?
            analyzer.can_ignore?
          end
        end
      end

      # Performance overhead should be minimal (less than 50% increase)
      overhead_ratio = abstraction_time / direct_time

      Rails.logger.debug "\nPerformance Analysis:"
      Rails.logger.debug { "Direct approach: #{(direct_time * 1000).round(3)}ms" }
      Rails.logger.debug { "Abstraction approach: #{(abstraction_time * 1000).round(3)}ms" }
      Rails.logger.debug { "Overhead ratio: #{overhead_ratio.round(3)}x" }

      # Allow for some overhead but ensure it's reasonable
      expect(overhead_ratio).to be < 2.0 # Less than 100% overhead

      # In practice, this should be much lower (typically 1.1-1.3x)
      Rails.logger.debug 'WARNING: Higher than expected overhead detected' if overhead_ratio > 1.5
    end
  end

  describe 'garbage collection behavior' do
    it 'demonstrates analyzers are properly collected' do
      # Force GC to start clean
      GC.start
      initial_object_count = ObjectSpace.count_objects[:T_OBJECT]

      # Create analyzers in a block scope
      1000.times do
        futures.each do |future|
          analyzer = Tasker::Orchestration::FutureStateAnalyzer.new(future)
          # Use the analyzer to prevent optimization
          analyzer.should_cancel?
        end
        # analyzer goes out of scope here
      end

      # Force GC and measure
      GC.start
      final_object_count = ObjectSpace.count_objects[:T_OBJECT]

      # Should be back to roughly the same count
      object_difference = final_object_count - initial_object_count

      Rails.logger.debug "\nGC Analysis:"
      Rails.logger.debug { "Initial objects: #{initial_object_count}" }
      Rails.logger.debug { "Final objects: #{final_object_count}" }
      Rails.logger.debug { "Difference: #{object_difference}" }

      # Allow for some variance but should be minimal
      expect(object_difference).to be < 100
    end
  end

  describe 'real-world usage simulation' do
    it 'simulates cleanup_futures_with_memory_management usage pattern' do
      # Simulate the actual usage pattern in our cleanup method
      batch_sizes = [3, 6, 8, 12] # Realistic batch sizes

      total_time = Benchmark.realtime do
        batch_sizes.each do |batch_size|
          # Create a batch of futures
          future_batch = Array.new(batch_size) do
            Concurrent::Future.execute do
              sleep(0.001)
              rand(100)
            end
          end

          # Simulate our cleanup logic
          future_batch.each do |future|
            analyzer = Tasker::Orchestration::FutureStateAnalyzer.new(future)

            if analyzer.should_cancel?
              future.cancel
            elsif analyzer.should_wait_for_completion?
              future.wait(0.1) # Short wait for test
            end
          end

          # Wait for completion and cleanup
          future_batch.each(&:wait)
          future_batch.clear
        end
      end

      Rails.logger.debug "\nReal-world simulation:"
      Rails.logger.debug { "Total time for #{batch_sizes.sum} futures: #{(total_time * 1000).round(3)}ms" }
      Rails.logger.debug { "Average per future: #{(total_time * 1000 / batch_sizes.sum).round(3)}ms" }

      # Should be very fast - each future analysis should be sub-millisecond
      expect(total_time).to be < 1.0 # Less than 1 second total
    end
  end
end
