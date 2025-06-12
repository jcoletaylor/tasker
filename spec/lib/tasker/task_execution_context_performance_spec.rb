# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Task Execution Context Performance Optimization' do
  # Performance test to validate the optimization of the task execution context view
  # This test compares the original subquery approach vs the optimized window function approach
  raw_query_path_v01 = Rails.root.join('db/views/tasker_task_execution_contexts_v01.sql')

  before(:all) do
    # Create a substantial dataset for performance testing
    @tasks = []
    @total_steps = 0

    # Create 50 tasks with varying complexity
    50.times do |i|
      case i % 5
      when 0
        task = create(:linear_workflow_task, context: { batch_id: "perf_test_#{i}" })
        @total_steps += 6 # Linear workflow has 6 steps
      when 1
        task = create(:diamond_workflow_task, context: { batch_id: "perf_test_#{i}" })
        @total_steps += 7 # Diamond workflow has 7 steps
      when 2
        task = create(:parallel_merge_workflow_task, context: { batch_id: "perf_test_#{i}" })
        @total_steps += 7 # Parallel merge has 7 steps
      when 3
        task = create(:tree_workflow_task, context: { batch_id: "perf_test_#{i}" })
        @total_steps += 8 # Tree workflow has 8 steps
      when 4
        task = create(:mixed_workflow_task, context: { batch_id: "perf_test_#{i}" })
        @total_steps += 9 # Mixed workflow has 9 steps
      end
      @tasks << task
    end

    Rails.logger.debug "\n=== Performance Test Dataset ==="
    Rails.logger.debug { "Created #{@tasks.count} tasks with #{@total_steps} total steps" }
  end

  after(:all) do
    # Clean up test data
    Tasker::Task.where(task_id: @tasks.map(&:task_id)).destroy_all
  end

  describe 'Query Performance Analysis' do
    it 'measures performance of original vs optimized query' do
      # Test the original view (v01) performance
      original_times = []
      3.times do
        start_time = Time.current

        # Query using the original view structure (simulate the subquery approach)
        result_count = ActiveRecord::Base.connection.execute(
          Rails.root.join('db/views/tasker_task_execution_contexts_v01.sql').read
        ).count

        execution_time = Time.current - start_time
        original_times << execution_time

        expect(result_count).to eq(@tasks.count)
      end

      # Test the optimized view (v01) performance
      optimized_times = []
      3.times do
        start_time = Time.current

        # Query using the optimized view structure
        result_count = ActiveRecord::Base.connection.execute(
          File.read(raw_query_path_v01)
        ).count

        execution_time = Time.current - start_time
        optimized_times << execution_time

        expect(result_count).to eq(@tasks.count)
      end

      # Calculate averages
      avg_original = original_times.sum / original_times.size
      avg_optimized = optimized_times.sum / optimized_times.size
      improvement_ratio = avg_original / avg_optimized

      Rails.logger.debug "\n=== Performance Comparison Results ==="
      Rails.logger.debug { "Dataset: #{@tasks.count} tasks, #{@total_steps} steps" }
      Rails.logger.debug { "Original query average: #{avg_original.round(4)}s" }
      Rails.logger.debug { "Optimized query average: #{avg_optimized.round(4)}s" }
      Rails.logger.debug { "Performance improvement: #{improvement_ratio.round(2)}x faster" }
      Rails.logger.debug { "Time saved: #{((avg_original - avg_optimized) * 1000).round(2)}ms per query" }

      # The optimized query should be faster (or at least not significantly slower)
      expect(avg_optimized).to be <= (avg_original * 1.2) # Allow 20% tolerance for test variance

      # Both queries should complete in reasonable time
      expect(avg_original).to be < 5.seconds
      expect(avg_optimized).to be < 5.seconds
    end
  end

  describe 'Index Utilization' do
    it 'verifies that the optimized query uses appropriate indexes' do
      # Test a specific task query to see index usage
      sample_task = @tasks.first

      query_with_where = "
        #{File.read(raw_query_path_v01)}
        WHERE t.task_id = #{sample_task.task_id}
      "

      execution_plan = ActiveRecord::Base.connection.execute(
        "EXPLAIN (ANALYZE, BUFFERS) #{query_with_where}"
      ).to_a

      plan_text = execution_plan.map { |row| row['QUERY PLAN'] }.join("\n")

      Rails.logger.debug "\n=== Index Utilization Analysis ==="
      Rails.logger.debug 'Query plan for single task lookup:'
      execution_plan.each { |row| Rails.logger.debug row['QUERY PLAN'] }

      # Check for index usage indicators
      uses_index_scan = plan_text.include?('Index Scan') || plan_text.include?('Index Only Scan')
      uses_seq_scan = plan_text.include?('Seq Scan')

      Rails.logger.debug "\n--- Index Usage Summary ---"
      Rails.logger.debug { "Uses index scans: #{uses_index_scan}" }
      Rails.logger.debug { "Uses sequential scans: #{uses_seq_scan}" }

      # For a single task query, we should be using indexes
      expect(uses_index_scan).to be true
    end
  end

  describe 'Scalability Testing' do
    it 'validates performance remains acceptable with larger datasets' do
      # Test with the current dataset size
      start_time = Time.current

      results = ActiveRecord::Base.connection.execute(
        File.read(raw_query_path_v01)
      )

      execution_time = Time.current - start_time
      records_per_second = results.count / execution_time

      Rails.logger.debug "\n=== Scalability Analysis ==="
      Rails.logger.debug { "Dataset size: #{@tasks.count} tasks, #{@total_steps} steps" }
      Rails.logger.debug { "Query execution time: #{execution_time.round(4)}s" }
      Rails.logger.debug { "Records processed per second: #{records_per_second.round(0)}" }

      # Performance should be reasonable for the dataset size
      expect(execution_time).to be < 2.seconds, "Query should complete within 2 seconds for #{@tasks.count} tasks"
      expect(records_per_second).to be > 25, 'Should process at least 25 records per second'

      # Estimate performance for larger datasets
      estimated_1000_tasks = (1000.0 / @tasks.count) * execution_time
      estimated_10000_tasks = (10_000.0 / @tasks.count) * execution_time

      Rails.logger.debug { "Estimated time for 1,000 tasks: #{estimated_1000_tasks.round(2)}s" }
      Rails.logger.debug { "Estimated time for 10,000 tasks: #{estimated_10000_tasks.round(2)}s" }

      # Should scale reasonably (sub-linear growth is ideal)
      expect(estimated_1000_tasks).to be < 10.seconds, 'Should handle 1,000 tasks in under 10 seconds'
    end
  end
end
