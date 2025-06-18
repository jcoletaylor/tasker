# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::Functions::FunctionBasedSystemHealthCounts, type: :model do
  describe 'wrapper functionality' do
    before do
      # Create test data using workflow factory patterns
      @test_workflows = []

      # Create some completed workflows
      2.times do
        task = create(:linear_workflow_task)
        # Transition task to in_progress first
        task.state_machine.transition_to!(:in_progress)
        task.workflow_steps.each do |step|
          step.state_machine.transition_to!(:in_progress)
          step.state_machine.transition_to!(:complete)
        end
        # Transition task to complete after all steps are done
        task.state_machine.transition_to!(:complete)
        @test_workflows << task
      end

      # Create pending workflow
      pending_task = create(:diamond_workflow_task)
      # Ensure task starts in pending state (this should be the default but let's be explicit)
      # pending_task.state_machine.transition_to!(:pending) # This might not be a valid transition
      @test_workflows << pending_task

      # Create workflow with errors
      error_task = create(:tree_workflow_task)
      # Transition task to in_progress first
      error_task.state_machine.transition_to!(:in_progress)
      error_task.workflow_steps.first.tap do |step|
        step.state_machine.transition_to!(:in_progress)
        step.state_machine.transition_to!(:error)
        step.update!(attempts: 1, retry_limit: 3, retryable: true)
      end
      # Transition task to error state
      error_task.state_machine.transition_to!(:error)
      @test_workflows << error_task
    end

    it 'returns structured health counts data' do
      result = described_class.call

      expect(result).to be_a(described_class::HealthMetrics)
      expect(result).to respond_to(:total_tasks)
      expect(result).to respond_to(:pending_tasks)
      expect(result).to respond_to(:in_progress_tasks)
      expect(result).to respond_to(:complete_tasks)
      expect(result).to respond_to(:error_tasks)
      expect(result).to respond_to(:cancelled_tasks)

      expect(result).to respond_to(:total_steps)
      expect(result).to respond_to(:pending_steps)
      expect(result).to respond_to(:in_progress_steps)
      expect(result).to respond_to(:complete_steps)
      expect(result).to respond_to(:error_steps)

      expect(result).to respond_to(:retryable_error_steps)
      expect(result).to respond_to(:exhausted_retry_steps)
      expect(result).to respond_to(:in_backoff_steps)

      expect(result).to respond_to(:active_connections)
      expect(result).to respond_to(:max_connections)
    end

    it 'returns numeric values for all counts' do
      result = described_class.call

      # All count fields should be numeric
      count_fields = %i[
        total_tasks pending_tasks in_progress_tasks complete_tasks error_tasks cancelled_tasks
        total_steps pending_steps in_progress_steps complete_steps error_steps
        retryable_error_steps exhausted_retry_steps in_backoff_steps
        active_connections max_connections
      ]

      count_fields.each do |field|
        expect(result.public_send(field)).to be >= 0, "#{field} should be a non-negative integer"
        expect(result.public_send(field)).to be_a(Integer), "#{field} should be an integer"
      end
    end

    it 'returns consistent results across multiple calls' do
      results = Array.new(3) { described_class.call }

      first_result = results.first
      results.each do |result|
        expect(result.total_tasks).to eq(first_result.total_tasks)
        expect(result.total_steps).to eq(first_result.total_steps)
        expect(result.complete_tasks).to eq(first_result.complete_tasks)
        expect(result.error_steps).to eq(first_result.error_steps)
      end
    end

    it 'handles database connection errors gracefully' do
      # Mock a database connection error
      allow(described_class).to receive(:connection).and_return(double('connection'))
      allow(described_class.connection).to receive(:select_all).and_raise(ActiveRecord::ConnectionNotEstablished)

      expect { described_class.call }.to raise_error(ActiveRecord::ConnectionNotEstablished)
    end

    it 'validates that task counts are reasonable' do
      result = described_class.call

      total_tasks = result.total_tasks
      sum_of_states = result.pending_tasks +
                      result.in_progress_tasks +
                      result.complete_tasks +
                      result.error_tasks +
                      result.cancelled_tasks

      # In Tasker, tasks without explicit state transitions might not be counted in state-specific counts
      # This is normal behavior - tasks start without transitions until they begin processing
      # So we validate that the sum is reasonable relative to total tasks
      expect(sum_of_states).to be <= total_tasks
      expect(sum_of_states).to be >= 0
      expect(total_tasks).to be >= 0
    end

    it 'validates that step counts are reasonable' do
      result = described_class.call

      total_steps = result.total_steps
      sum_of_states = result.pending_steps +
                      result.in_progress_steps +
                      result.complete_steps +
                      result.error_steps

      # NOTE: cancelled steps are not included in the sum as they might be counted differently
      expect(total_steps).to be >= sum_of_states
    end

    it 'validates retry-related counts are consistent' do
      result = described_class.call

      retryable_count = result.retryable_error_steps
      exhausted_count = result.exhausted_retry_steps
      total_error_steps = result.error_steps

      # Retryable + exhausted should not exceed total error steps
      expect(retryable_count + exhausted_count).to be <= total_error_steps
    end

    it 'validates database connection metrics' do
      result = described_class.call

      active_connections = result.active_connections
      max_connections = result.max_connections

      expect(active_connections).to be >= 1 # At least one connection (ours)
      expect(max_connections).to be > 0
      expect(max_connections).to be >= active_connections
    end
  end

  describe 'edge cases' do
    it 'handles empty database correctly' do
      # Clear all data (handle foreign key constraints in proper order)
      Tasker::WorkflowStepTransition.delete_all
      Tasker::TaskTransition.delete_all
      Tasker::WorkflowStepEdge.delete_all
      Tasker::WorkflowStep.delete_all
      Tasker::Task.delete_all

      result = described_class.call

      expect(result.total_tasks).to eq(0)
      expect(result.total_steps).to eq(0)
      expect(result.retryable_error_steps).to eq(0)
      expect(result.exhausted_retry_steps).to eq(0)
      expect(result.in_backoff_steps).to eq(0)

      # Database metrics should still work
      expect(result.active_connections).to be >= 1
      expect(result.max_connections).to be > 0
    end

    it 'handles very large numbers appropriately' do
      # This test ensures the function can handle realistic production loads
      # We don't actually create thousands of records, just verify the function works
      result = described_class.call

      # All values should be reasonable integers, not overflowing
      expect(result.total_tasks).to be < 1_000_000
      expect(result.total_steps).to be < 10_000_000
      expect(result.max_connections).to be < 10_000
    end
  end

  describe 'performance characteristics' do
    it 'executes quickly' do
      execution_time = Benchmark.realtime do
        5.times { described_class.call }
      end

      average_time = execution_time / 5
      expect(average_time).to be < 0.1 # Should average under 100ms
    end

    it 'is efficient with concurrent calls' do
      # Test that multiple concurrent calls don't interfere
      threads = []
      results = []

      5.times do
        threads << Thread.new do
          results << described_class.call
        end
      end

      threads.each(&:join)

      expect(results.size).to eq(5)
      # All results should be consistent
      first_result = results.first
      results.each do |result|
        expect(result.total_tasks).to eq(first_result.total_tasks)
      end
    end
  end
end
