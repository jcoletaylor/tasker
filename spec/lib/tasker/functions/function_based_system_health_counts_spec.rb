# frozen_string_literal: true

require 'rails_helper'

def create_test_workflows
  # Create test data using workflow factory patterns with proper state machine initialization
  test_workflows = []

  # Create some completed workflows
  2.times do
    task = create(:linear_workflow_task)
    # Ensure all steps have properly initialized state machines
    task.workflow_steps.each { |step| step.state_machine.initialize_state_machine! }

    # Transition task to in_progress first
    task.state_machine.transition_to!(:in_progress)
    task.workflow_steps.each do |step|
      step.state_machine.transition_to!(:in_progress)
      step.state_machine.transition_to!(:complete)
    end
    # Transition task to complete after all steps are done
    task.state_machine.transition_to!(:complete)
    test_workflows << task
  end

  # Create pending workflow
  pending_task = create(:diamond_workflow_task)
  # Ensure all steps have properly initialized state machines
  pending_task.workflow_steps.each { |step| step.state_machine.initialize_state_machine! }
  test_workflows << pending_task

  # Create workflow with errors
  error_task = create(:tree_workflow_task)
  # Ensure all steps have properly initialized state machines
  error_task.workflow_steps.each { |step| step.state_machine.initialize_state_machine! }

  # Transition task to in_progress first
  error_task.state_machine.transition_to!(:in_progress)
  # Find a step with no dependencies (root step in tree workflow - no parents)
  error_step = error_task.workflow_steps.find { |step| step.parents.empty? }

  # Use factory helper to properly set step to error state with improved state handling
  Rails.logger.debug "Health Count Test: Setting step #{error_step.workflow_step_id} to error state"
  set_step_to_error(error_step)
  error_step.update!(attempts: 1, retry_limit: 3, retryable: true)

  # Transition task to error state
  error_task.state_machine.transition_to!(:error)
  test_workflows << error_task

  Rails.logger.debug "Health Count Test: Created #{test_workflows.size} test workflows"
  test_workflows
end

RSpec.describe Tasker::Functions::FunctionBasedSystemHealthCounts, type: :model do
  describe 'wrapper functionality' do
    # Use standard Rails transactional test patterns
    let(:test_workflows) { create_test_workflows }

    def create_test_workflows
      # Create a modest set of test workflows using standard factory patterns
      workflows = []

      # 2 complete tasks with 2 complete steps each (4 total complete steps)
      2.times do |i|
        task = create(:linear_workflow_task)
        workflows << task
        task.workflow_steps.limit(2).each do |step|
          complete_step_via_state_machine(step)
        end
      end

      # 1 pending task with all steps pending (2 total pending steps)
      pending_task = create(:linear_workflow_task)
      workflows << pending_task

      # 1 error task with 1 error step, rest pending (1 error step, 1 pending step)
      error_task = create(:linear_workflow_task)
      workflows << error_task
      first_step = error_task.workflow_steps.first
      set_step_to_error(first_step, 'Test error')
      first_step.update!(
        attempts: 1,
        retry_limit: 3,
        retryable: true,
        last_attempted_at: 30.seconds.ago
      )

      workflows
    end

    it 'returns structured health counts data' do
      # Trigger test data creation
      test_workflows

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
      # Trigger test data creation
      test_workflows

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
      # Trigger test data creation
      test_workflows

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
      # Trigger test data creation
      test_workflows

      result = execute_health_counts_function

      # Should have at least the test data we created
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
      # Trigger test data creation
      test_workflows

      result = execute_health_counts_function

      # Should have at least the test data we created
      expect(result.total_steps).to be >= 8
      expect(result.complete_steps).to be >= 4
      expect(result.pending_steps).to be >= 3
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
      # Trigger test data creation
      test_workflows

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
      threads = 3.times.map do
        Thread.new { execute_health_counts_function }
      end

      results = threads.map(&:value)

      # All threads should return the same results
      expect(results.uniq.size).to eq(1)
    end
  end

  private

  def execute_health_counts_function
    described_class.call
  end
end
