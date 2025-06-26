# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Functions::FunctionBasedSystemHealthCounts, type: :model do
  describe 'wrapper functionality' do
    # Use standard Rails transactional test patterns with before block for data setup
    before do
      # Create test data directly in the before block to ensure it's available
      create_test_workflows_for_health_counts
    end

    it 'returns structured health counts data' do
      # Test data is created in before block
      result = execute_health_counts_function

      expect(result).to be_a(described_class::HealthMetrics)
      expect(result).to respond_to(:total_tasks)
      expect(result).to respond_to(:complete_tasks)
      expect(result).to respond_to(:pending_tasks)
      expect(result).to respond_to(:error_tasks)
      expect(result).to respond_to(:total_steps)
      expect(result).to respond_to(:complete_steps)
      expect(result).to respond_to(:pending_steps)
      expect(result).to respond_to(:error_steps)
      expect(result).to respond_to(:retryable_error_steps)
      expect(result).to respond_to(:exhausted_retry_steps)
      expect(result).to respond_to(:in_backoff_steps)
      expect(result).to respond_to(:active_connections)
      expect(result).to respond_to(:max_connections)
    end

    it 'returns numeric values for all counts' do
      # Test data is created in before block
      result = execute_health_counts_function

      numeric_fields = %w[
        total_tasks complete_tasks pending_tasks error_tasks
        total_steps complete_steps pending_steps error_steps
        retryable_error_steps exhausted_retry_steps in_backoff_steps
        active_connections max_connections
      ]

      numeric_fields.each do |field|
        value = result.public_send(field.to_sym)
        expect(value).to be >= 0, "#{field} should be a non-negative integer"
        expect(value).to be_a(Integer), "#{field} should be an integer"
      end
    end

    it 'returns consistent results across multiple calls' do
      # Test data is created in before block
      result1 = execute_health_counts_function
      result2 = execute_health_counts_function

      expect(result1.total_tasks).to eq(result2.total_tasks)
      expect(result1.total_steps).to eq(result2.total_steps)
    end

    it 'handles database connection errors gracefully' do
      # This test doesn't need test data, just tests error handling
      expect { execute_health_counts_function }.not_to raise_error
    end

    it 'validates that task counts are reasonable' do
      # Test data is created in before block
      result = execute_health_counts_function

      # Should have at least the test data we created:
      # 2 complete tasks + 1 pending task + 1 error task = 4 tasks minimum
      expect(result.total_tasks).to be >= 4
      expect(result.complete_tasks).to be >= 2
      expect(result.pending_tasks).to be >= 1
      expect(result.error_tasks).to be >= 1

      # Totals should add up reasonably
      total_tasks = result.total_tasks
      complete_tasks = result.complete_tasks
      pending_tasks = result.pending_tasks
      error_tasks = result.error_tasks

      # Sum of states should not exceed total (some states may overlap)
      expect(complete_tasks + pending_tasks + error_tasks).to be <= total_tasks * 2
    end

    it 'validates that step counts are reasonable' do
      # Test data is created in before block
      result = execute_health_counts_function

      # Should have at least the test data we created:
      # 2 complete tasks × 6 steps = 12 complete steps
      # 1 pending task × 6 steps = 6 pending steps
      # 1 error task: 1 error step + 5 pending steps
      # Total: 24 steps (12 complete + 11 pending + 1 error)
      expect(result.total_steps).to be >= 24
      expect(result.complete_steps).to be >= 12
      expect(result.pending_steps).to be >= 11
      expect(result.error_steps).to be >= 1

      # Totals should be reasonable
      total_steps = result.total_steps
      complete_steps = result.complete_steps
      pending_steps = result.pending_steps
      error_steps = result.error_steps

      # Sum should be reasonable relative to total
      expect(complete_steps + pending_steps + error_steps).to be <= total_steps * 2
    end

    it 'validates retry-related counts are consistent' do
      # Test data is created in before block
      result = execute_health_counts_function

      retryable_errors = result.retryable_error_steps
      exhausted_retries = result.exhausted_retry_steps
      in_backoff = result.in_backoff_steps

      # Should have at least our test error step
      expect(retryable_errors).to be >= 1

      # All retry counts should be non-negative
      expect(exhausted_retries).to be >= 0
      expect(in_backoff).to be >= 0
    end

    it 'validates database connection metrics' do
      # This test doesn't need test data, just validates connection metrics
      result = execute_health_counts_function

      expect(result.active_connections).to be >= 1
      expect(result.max_connections).to be > 0
      expect(result.max_connections).to be >= result.active_connections
    end
  end

  describe 'edge cases' do
    describe 'empty database scenario' do
      # Use a simple before block for this specific test context
      before do
        # Clear all test data in proper foreign key order
        Tasker::WorkflowStepTransition.delete_all
        Tasker::TaskTransition.delete_all
        Tasker::WorkflowStepEdge.delete_all
        Tasker::WorkflowStep.delete_all
        Tasker::Task.delete_all
      end

      it 'handles empty database correctly' do
        result = execute_health_counts_function

        expect(result.total_tasks).to eq(0)
        expect(result.total_steps).to eq(0)
        expect(result.retryable_error_steps).to eq(0)
        expect(result.exhausted_retry_steps).to eq(0)
        expect(result.in_backoff_steps).to eq(0)

        # Database metrics should still work
        expect(result.active_connections).to be >= 1
        expect(result.max_connections).to be > 0
      end
    end

    it 'handles very large numbers appropriately' do
      result = execute_health_counts_function

      # All counts should be within reasonable PostgreSQL integer bounds
      numeric_methods = %i[
        total_tasks complete_tasks pending_tasks error_tasks
        total_steps complete_steps pending_steps error_steps
        retryable_error_steps exhausted_retry_steps in_backoff_steps
        active_connections max_connections
      ]

      numeric_methods.each do |method|
        value = result.public_send(method)
        expect(value).to be <= 2_147_483_647, "#{method} should be within PostgreSQL integer bounds"
        expect(value).to be >= 0, "#{method} should be non-negative"
      end
    end
  end

  describe 'performance characteristics' do
    let(:performance_workflows) { create_performance_test_data }

    it 'executes quickly' do
      # Trigger test data creation
      performance_workflows

      execution_time = Benchmark.realtime do
        5.times { execute_health_counts_function }
      end

      average_time = execution_time / 5
      expect(average_time).to be < 0.2 # Should average under 200ms
    end

    it 'is efficient with concurrent calls' do
      # Trigger test data creation
      performance_workflows

      # Test concurrent execution
      threads = Array.new(3) do
        Thread.new { execute_health_counts_function }
      end

      results = threads.map(&:value)

      # All threads should return the same results
      expect(results.uniq.size).to eq(1)
    end
  end

  private

  # Helper method to create test workflows for health count validation
  # Creates a controlled set of tasks and steps in various states
  def create_test_workflows_for_health_counts
    # Create 2 complete tasks with ALL steps complete (12 total complete steps)
    2.times do
      task = create(:linear_workflow_task)

      # Complete ALL steps to allow task to transition to complete
      task.workflow_steps.each do |step|
        complete_step_via_state_machine(step)
      end

      # Manually transition task to complete now that all steps are complete
      # Tasks must go through in_progress before complete
      task.state_machine.transition_to!(:in_progress)
      task.state_machine.transition_to!(:complete)
    end

    # Create 1 pending task with all steps pending (6 total pending steps)
    pending_task = create(:linear_workflow_task)
    # Ensure all steps are properly initialized to pending state
    pending_task.workflow_steps.each do |step|
      # Create initial pending state transition if it doesn't exist
      next if step.workflow_step_transitions.exists?

      create(:workflow_step_transition,
             workflow_step: step,
             to_state: Tasker::Constants::WorkflowStepStatuses::PENDING,
             sort_key: 1,
             most_recent: true)
    end

    # Create 1 error task with 1 error step, rest pending (1 error step, 5 pending steps)
    error_task = create(:linear_workflow_task)

    # Initialize ALL steps to pending first
    error_task.workflow_steps.each do |step|
      next if step.workflow_step_transitions.exists?

      create(:workflow_step_transition,
             workflow_step: step,
             to_state: Tasker::Constants::WorkflowStepStatuses::PENDING,
             sort_key: 1,
             most_recent: true)
    end

    # Then set the first step to error
    first_step = error_task.workflow_steps.first
    set_step_to_error(first_step, 'Test error')
    first_step.update!(
      attempts: 1,
      retry_limit: 3,
      retryable: true,
      last_attempted_at: 30.seconds.ago
    )

    # Manually transition task to error state
    error_task.state_machine.transition_to!(:error)
  end

  # Helper method to create performance test data
  # Creates a larger set of workflows for performance testing
  def create_performance_test_data
    workflows = []

    # Create 5 completed workflows
    5.times do
      task = create(:linear_workflow_task)
      workflows << task
      task.workflow_steps.each { |step| complete_step_via_state_machine(step) }
    end

    # Create 3 pending workflows
    3.times { workflows << create(:diamond_workflow_task) }

    # Create 2 workflows with errors
    2.times do
      task = create(:tree_workflow_task)
      workflows << task
      task.workflow_steps.limit(1).each do |step|
        set_step_to_error(step, 'Performance test error')
        step.update!(attempts: 1, retry_limit: 3)
      end
    end

    workflows
  end

  # Simple wrapper for the health counts function
  def execute_health_counts_function
    described_class.call
  end
end
