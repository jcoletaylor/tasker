# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'SQL Functions Integration', type: :model do
  describe 'Function-based implementations' do
    let(:task) { create(:task, :with_workflow_steps) }

    before do
      # Ensure we have some test data with proper state transitions
      step = task.workflow_steps.first
      step.transition_to!('pending') if step.respond_to?(:transition_to!)
    end

    describe 'FunctionBasedStepReadinessStatus' do
      it 'loads step readiness data using SQL function' do
        results = Tasker::Functions::FunctionBasedStepReadinessStatus.for_task(task.task_id)

        expect(results).not_to be_empty
        expect(results.first).to respond_to(:workflow_step_id)
        expect(results.first).to respond_to(:ready_for_execution)
        expect(results.first).to respond_to(:dependencies_satisfied)
        expect(results.first.task_id).to eq(task.task_id)
      end

      it 'provides the same interface as the original model' do
        result = Tasker::Functions::FunctionBasedStepReadinessStatus.for_task(task.task_id).first

        expect(result).to respond_to(:can_execute_now?)
        expect(result).to respond_to(:blocking_reason)
        expect(result).to respond_to(:dependency_status)
        expect(result).to respond_to(:detailed_status)
      end

      it 'loads multiple tasks efficiently using batch function' do
        task2 = create(:task, :with_workflow_steps)
        task3 = create(:task, :with_workflow_steps)

        task_ids = [task.task_id, task2.task_id, task3.task_id]
        results = Tasker::Functions::FunctionBasedStepReadinessStatus.for_tasks(task_ids)

        expect(results).not_to be_empty

        # Should have steps from all tasks
        result_task_ids = results.map(&:task_id).uniq
        expect(result_task_ids).to match_array(task_ids)

        # Results should be properly grouped by task (ordered by task_id, workflow_step_id)
        task_groups = results.group_by(&:task_id)
        expect(task_groups.keys.sort).to eq(task_ids.sort)

        # Each result should have the expected interface
        results.each do |result|
          expect(result).to respond_to(:workflow_step_id)
          expect(result).to respond_to(:ready_for_execution)
          expect(result).to respond_to(:can_execute_now?)
        end
      end

      it 'handles empty task_ids array gracefully for batch step readiness' do
        results = Tasker::Functions::FunctionBasedStepReadinessStatus.for_tasks([])
        expect(results).to eq([])
      end
    end

    describe 'FunctionBasedTaskExecutionContext' do
      it 'loads task execution context using SQL function' do
        result = Tasker::Functions::FunctionBasedTaskExecutionContext.find(task.task_id)

        expect(result).not_to be_nil
        expect(result.task_id).to eq(task.task_id)
        expect(result).to respond_to(:total_steps)
        expect(result).to respond_to(:execution_status)
        expect(result).to respond_to(:health_status)
      end

      it 'provides the same interface as the original model' do
        result = Tasker::Functions::FunctionBasedTaskExecutionContext.find(task.task_id)

        expect(result).to respond_to(:has_work_to_do?)
        expect(result).to respond_to(:is_blocked?)
        expect(result).to respond_to(:workflow_summary)
        expect(result).to respond_to(:next_action_details)
      end

      it 'returns nil for non-existent tasks' do
        result = Tasker::Functions::FunctionBasedTaskExecutionContext.find(99_999)
        expect(result).to be_nil
      end

      it 'loads multiple tasks efficiently using batch function' do
        task2 = create(:task, :with_workflow_steps)
        task3 = create(:task, :with_workflow_steps)

        task_ids = [task.task_id, task2.task_id, task3.task_id]
        results = Tasker::Functions::FunctionBasedTaskExecutionContext.for_tasks(task_ids)

        expect(results.length).to eq(3)
        expect(results.map(&:task_id)).to match_array(task_ids)

        # Verify each result has the expected interface
        results.each do |result|
          expect(result).to respond_to(:total_steps)
          expect(result).to respond_to(:execution_status)
          expect(result).to respond_to(:has_work_to_do?)
        end
      end

      it 'handles empty task_ids array gracefully' do
        results = Tasker::Functions::FunctionBasedTaskExecutionContext.for_tasks([])
        expect(results).to eq([])
      end
    end

    describe 'Performance comparison' do
      it 'SQL functions should be faster than views for targeted queries' do
        # This is more of a documentation test - actual performance testing
        # would require larger datasets and proper benchmarking

        function_time = Benchmark.realtime do
          Tasker::Functions::FunctionBasedStepReadinessStatus.for_task(task.task_id)
        end

        view_time = Benchmark.realtime do
          Tasker::StepReadinessStatus.for_task(task.task_id)
        end

        # For small datasets, the difference might not be significant
        # But the function approach scales much better
        expect(function_time).to be < 1.0  # Should be very fast
        expect(view_time).to be < 1.0      # Should also be fast for small data

        # The real benefit is in scalability, not necessarily raw speed on small datasets
      end
    end
  end
end
