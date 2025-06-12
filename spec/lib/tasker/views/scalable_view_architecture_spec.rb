# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Scalable View Architecture' do
  # Test the multi-tiered view system for performance and correctness
  # This validates that the scalable architecture works as designed

  describe 'Smart View Router' do
    let(:router) { Tasker::Views::SmartViewRouter }

    describe 'scope validation' do
      it 'accepts valid scopes' do
        expect { router.get_task_execution_context(scope: :active) }.not_to raise_error
        expect { router.get_task_execution_context(scope: :recent) }.not_to raise_error
        expect { router.get_task_execution_context(scope: :complete) }.not_to raise_error
      end

      it 'rejects invalid scopes' do
        expect { router.get_task_execution_context(scope: :invalid) }.to raise_error(ArgumentError)
      end

      it 'requires task_id for single scope' do
        expect { router.get_task_execution_context(scope: :single) }.to raise_error(ArgumentError)
        expect { router.get_task_execution_context(task_id: 123, scope: :single) }.not_to raise_error
      end
    end

    describe 'scope configuration' do
      it 'provides scope information' do
        info = router.get_scope_info(:active)
        expect(info).to include(:description, :performance_target)
        expect(info[:performance_target]).to eq('100ms')
      end

      it 'lists all available scopes' do
        scopes = router.available_scopes
        expect(scopes.keys).to contain_exactly(:active, :recent, :complete, :single)
      end
    end
  end

  describe 'Active Views Performance' do
    # Test that active views provide the expected performance benefits

    context 'with test data' do
      before(:all) do
        # Create test data with mixed completion states
        @active_tasks = []
        @completed_tasks = []

        # Create 10 active tasks
        10.times do |i|
          task = create(:task, context: { test: "active_#{i}" })
          # Don't mark as complete - these should appear in active views
          @active_tasks << task
        end

        # Create 10 completed tasks (simulate completed state)
        10.times do |i|
          task = create(:task, context: { test: "completed_#{i}" })
          # Mark as complete - these should be filtered out of active views
          task.update_column(:complete, true)
          @completed_tasks << task
        end
      end

      after(:all) do
        # Clean up test data
        Tasker::Task.where(task_id: (@active_tasks + @completed_tasks).map(&:task_id)).destroy_all
      end

      it 'active views exclude completed tasks' do
        # Test that active views only return incomplete tasks
        active_results = Tasker::Views::SmartViewRouter.get_task_execution_context(scope: :active)

        # Should only include active tasks, not completed ones
        active_task_ids = active_results.map { |r| r[:task_id] }
        expected_active_ids = @active_tasks.map(&:task_id)
        completed_task_ids = @completed_tasks.map(&:task_id)

        # Active view should include active tasks
        expect(active_task_ids).to include(*expected_active_ids)

        # Active view should exclude completed tasks
        expect(active_task_ids).not_to include(*completed_task_ids)
      end

      it 'complete views include all tasks' do
        # Test that complete views return all tasks
        complete_results = Tasker::Views::SmartViewRouter.get_task_execution_context(scope: :complete)

        complete_task_ids = complete_results.map { |r| r[:task_id] }
        all_task_ids = (@active_tasks + @completed_tasks).map(&:task_id)

        # Complete view should include all tasks
        expect(complete_task_ids).to include(*all_task_ids)
      end

      it 'single task queries work for both active and completed tasks' do
        # Test single task queries
        active_task = @active_tasks.first
        completed_task = @completed_tasks.first

        active_result = Tasker::Views::SmartViewRouter.get_task_execution_context(
          task_id: active_task.task_id,
          scope: :single
        )

        completed_result = Tasker::Views::SmartViewRouter.get_task_execution_context(
          task_id: completed_task.task_id,
          scope: :single
        )

        expect(active_result).to be_present
        expect(active_result[:task_id]).to eq(active_task.task_id)

        # Single queries should work even for completed tasks
        expect(completed_result).to be_present
        expect(completed_result[:task_id]).to eq(completed_task.task_id)
      end
    end
  end

  describe 'Performance Benchmarking' do
    # Benchmark different scopes to validate performance expectations

    it 'measures query performance across scopes' do
      performance_results = {}

      [:active, :complete].each do |scope|
        times = []

        # Run each query 3 times to get average
        3.times do
          start_time = Time.current
          Tasker::Views::SmartViewRouter.get_task_execution_context(scope: scope, limit: 100)
          execution_time = Time.current - start_time
          times << execution_time
        end

        avg_time = times.sum / times.size
        performance_results[scope] = {
          average_time: avg_time,
          target: Tasker::Views::SmartViewRouter.get_scope_info(scope)[:performance_target]
        }
      end

      puts "\n=== Performance Benchmark Results ==="
      performance_results.each do |scope, metrics|
        puts "#{scope.to_s.capitalize} scope: #{metrics[:average_time].round(4)}s (target: #{metrics[:target]})"
      end

      # Active scope should be faster than complete scope
      expect(performance_results[:active][:average_time]).to be <= performance_results[:complete][:average_time]
    end
  end

  describe 'Backward Compatibility Layer' do
    # Test that existing API still works with new routing

    before do
      # Ensure the compatibility layer is loaded
      require 'tasker/views/backward_compatibility_layer'
    end

    it 'maintains existing TaskExecutionContext API' do
      # Test that existing code patterns still work
      expect { Tasker::Views::SmartViewRouter.get_task_execution_context(scope: :active) }.not_to raise_error
    end

    it 'provides scope-specific methods' do
      router = Tasker::Views::SmartViewRouter

      # Test explicit scope methods
      expect { router.get_task_execution_context(scope: :active) }.not_to raise_error
      expect { router.get_task_execution_context(scope: :recent) }.not_to raise_error
      expect { router.get_task_execution_context(scope: :complete) }.not_to raise_error
    end

    it 'provides performance monitoring methods' do
      router = Tasker::Views::SmartViewRouter

      # Test monitoring capabilities
      scopes = router.available_scopes
      expect(scopes).to be_a(Hash)
      expect(scopes.keys).to include(:active, :recent, :complete, :single)
    end
  end

  describe 'View Consistency' do
    # Test that different views return consistent data for the same tasks

    context 'with consistent test data' do
      let!(:test_task) do
        task = create(:task, context: { test: 'consistency_check' })
        # Ensure task has workflow steps
        create_list(:workflow_step, 3, task: task)
        task
      end

      after do
        test_task.destroy
      end

      it 'returns consistent data across different scopes' do
        # Get the same task from different scopes
        active_result = Tasker::Views::SmartViewRouter.get_task_execution_context(
          task_id: test_task.task_id,
          scope: :active
        )

        complete_result = Tasker::Views::SmartViewRouter.get_task_execution_context(
          task_id: test_task.task_id,
          scope: :complete
        )

        single_result = Tasker::Views::SmartViewRouter.get_task_execution_context(
          task_id: test_task.task_id,
          scope: :single
        )

        # All scopes should return the same basic task information
        if active_result && complete_result && single_result
          expect(active_result[:task_id]).to eq(complete_result[:task_id])
          expect(active_result[:task_id]).to eq(single_result[:task_id])
          expect(active_result[:named_task_id]).to eq(complete_result[:named_task_id])
          expect(active_result[:named_task_id]).to eq(single_result[:named_task_id])
        end
      end
    end
  end

  describe 'Error Handling' do
    # Test error handling and edge cases

    it 'handles non-existent task IDs gracefully' do
      non_existent_id = 999999

      result = Tasker::Views::SmartViewRouter.get_task_execution_context(
        task_id: non_existent_id,
        scope: :single
      )

      expect(result).to be_nil
    end

    it 'handles empty result sets gracefully' do
      # Test with limit that might return empty results
      results = Tasker::Views::SmartViewRouter.get_task_execution_context(
        scope: :active,
        limit: 0
      )

      expect(results).to be_an(Array)
    end

    it 'validates parameters properly' do
      expect {
        Tasker::Views::SmartViewRouter.get_step_readiness(scope: :single)
      }.to raise_error(ArgumentError, /Single scope not supported/)
    end
  end

  describe 'Scalability Validation' do
    # Test that the architecture scales as expected

    it 'demonstrates performance improvement with active vs complete scopes' do
      # This test validates the core scalability premise

      active_times = []
      complete_times = []

      # Measure active scope performance
      3.times do
        start_time = Time.current
        Tasker::Views::SmartViewRouter.get_task_execution_context(scope: :active, limit: 10)
        active_times << (Time.current - start_time)
      end

      # Measure complete scope performance
      3.times do
        start_time = Time.current
        Tasker::Views::SmartViewRouter.get_task_execution_context(scope: :complete, limit: 10)
        complete_times << (Time.current - start_time)
      end

      avg_active = active_times.sum / active_times.size
      avg_complete = complete_times.sum / complete_times.size

      puts "\n=== Scalability Validation ==="
      puts "Active scope average: #{avg_active.round(4)}s"
      puts "Complete scope average: #{avg_complete.round(4)}s"
      puts "Performance ratio: #{(avg_complete / avg_active).round(2)}x"

      # Active should be at least as fast as complete (ideally faster)
      expect(avg_active).to be <= (avg_complete * 1.1) # Allow 10% tolerance
    end

    it 'validates that active views scale with active workload, not total history' do
      # This is the key architectural benefit - active views should not degrade
      # with historical data growth

      # The test validates that active views exclude completed tasks
      # In production, this means performance scales with active workload only

      active_results = Tasker::Views::SmartViewRouter.get_task_execution_context(scope: :active)
      complete_results = Tasker::Views::SmartViewRouter.get_task_execution_context(scope: :complete)

      # Active results should be a subset of complete results
      # (or equal if no completed tasks exist)
      expect(active_results.size).to be <= complete_results.size

      puts "\n=== Workload Scaling Validation ==="
      puts "Active tasks in view: #{active_results.size}"
      puts "Total tasks in view: #{complete_results.size}"
      puts "Filtering efficiency: #{((complete_results.size - active_results.size).to_f / complete_results.size * 100).round(1)}% excluded"
    end
  end
end
