# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'get_system_health_counts_v01 function', type: :model do
  include FactoryWorkflowHelpers
  describe 'system health counts accuracy' do
    before do
      # Clear any existing test data to ensure clean state
      Tasker::WorkflowStepTransition.delete_all
      Tasker::TaskTransition.delete_all
      Tasker::WorkflowStepEdge.delete_all
      Tasker::WorkflowStep.delete_all
      Tasker::Task.delete_all

      # Get baseline counts
      @baseline = execute_health_counts_function

      # Create simple test data with known changes
      # 2 complete tasks (6 steps each = 12 total steps)
      @complete_tasks = create_list(:linear_workflow_task, 2)
      @complete_tasks.each do |task|
        task.workflow_steps.each { |step| complete_step_via_state_machine(step) }
        task.task_transitions.create!(
          to_state: Tasker::Constants::TaskStatuses::COMPLETE,
          sort_key: 1,
          most_recent: true
        )
      end

      # 1 pending task (6 steps, all pending by default)
      @pending_tasks = create_list(:linear_workflow_task, 1)
      @pending_tasks.each do |task|
        # Ensure task has a pending transition
        task.task_transitions.create!(
          to_state: Tasker::Constants::TaskStatuses::PENDING,
          sort_key: 1,
          most_recent: true
        )
        # Ensure all steps have pending transitions
        task.workflow_steps.each do |step|
          step.workflow_step_transitions.create!(
            to_state: 'pending',
            sort_key: 1,
            most_recent: true
          )
        end
      end

      # 1 error task with 1 error step
      @error_tasks = create_list(:linear_workflow_task, 1)
      @error_tasks.each do |task|
        # Set first step to error with retry info
        first_step = task.workflow_steps.first
        set_step_to_error(first_step, 'Test error')
        first_step.update!(
          attempts: 1,
          retry_limit: 3,
          retryable: true,
          last_attempted_at: 30.seconds.ago
        )

        # Set remaining steps to pending
        task.workflow_steps.where.not(workflow_step_id: first_step.workflow_step_id).find_each do |step|
          step.workflow_step_transitions.create!(
            to_state: 'pending',
            sort_key: 1,
            most_recent: true
          )
        end

        task.task_transitions.create!(
          to_state: Tasker::Constants::TaskStatuses::ERROR,
          sort_key: 1,
          most_recent: true
        )
      end

      # Calculate expected changes (much more reliable)
      @expected_changes = {
        tasks: {
          total: 4,    # added 4 tasks
          complete: 2, # 2 complete tasks
          pending: 1,  # 1 pending task
          error: 1     # 1 error task
        },
        steps: {
          total: 24,   # added 24 steps (4 tasks × 6 steps each)
          complete: 12, # 12 complete steps (2 complete tasks × 6 steps each)
          pending: 11,  # 11 pending steps (1 pending task × 6 steps + 1 error task × 5 remaining steps)
          error: 1 # 1 error step
        },
        retries: {
          retryable_errors: 1,  # 1 retryable error step
          in_backoff: 1         # 1 step in backoff
        }
      }
    end

    it 'returns accurate task counts' do
      result = execute_health_counts_function

      # Check that counts increased by expected amounts
      expect(result['total_tasks'].to_i).to eq(@baseline['total_tasks'].to_i + @expected_changes[:tasks][:total])
      expect(result['complete_tasks'].to_i).to eq(@baseline['complete_tasks'].to_i + @expected_changes[:tasks][:complete])
      expect(result['pending_tasks'].to_i).to eq(@baseline['pending_tasks'].to_i + @expected_changes[:tasks][:pending])
      expect(result['error_tasks'].to_i).to eq(@baseline['error_tasks'].to_i + @expected_changes[:tasks][:error])
    end

    it 'returns accurate workflow step counts' do
      result = execute_health_counts_function

      # Check that step counts increased by expected amounts
      expect(result['total_steps'].to_i).to eq(@baseline['total_steps'].to_i + @expected_changes[:steps][:total])
      expect(result['complete_steps'].to_i).to eq(@baseline['complete_steps'].to_i + @expected_changes[:steps][:complete])
      expect(result['pending_steps'].to_i).to eq(@baseline['pending_steps'].to_i + @expected_changes[:steps][:pending])
      expect(result['error_steps'].to_i).to eq(@baseline['error_steps'].to_i + @expected_changes[:steps][:error])
    end

    it 'returns accurate retry-specific counts' do
      result = execute_health_counts_function

      # Check that retry counts increased by expected amounts
      expect(result['retryable_error_steps'].to_i).to eq(@baseline['retryable_error_steps'].to_i + @expected_changes[:retries][:retryable_errors])
      expect(result['in_backoff_steps'].to_i).to eq(@baseline['in_backoff_steps'].to_i + @expected_changes[:retries][:in_backoff])

      # Exhausted retries should not increase (our test error step is retryable)
      expect(result['exhausted_retry_steps'].to_i).to eq(@baseline['exhausted_retry_steps'].to_i)
    end

    it 'returns database connection metrics' do
      result = execute_health_counts_function

      expect(result['active_connections'].to_i).to be >= 1
      expect(result['max_connections'].to_i).to be > 0
      expect(result['max_connections'].to_i).to be >= result['active_connections'].to_i
    end

    it 'handles empty database correctly' do
      # Clear all test data (handle foreign key constraints)
      Tasker::WorkflowStepTransition.delete_all
      Tasker::TaskTransition.delete_all
      Tasker::WorkflowStepEdge.delete_all
      Tasker::WorkflowStep.delete_all
      Tasker::Task.delete_all

      result = execute_health_counts_function

      expect(result['total_tasks'].to_i).to eq(0)
      expect(result['total_steps'].to_i).to eq(0)
      expect(result['retryable_error_steps'].to_i).to eq(0)
      expect(result['exhausted_retry_steps'].to_i).to eq(0)
      expect(result['in_backoff_steps'].to_i).to eq(0)

      # Database metrics should still work
      expect(result['active_connections'].to_i).to be >= 1
      expect(result['max_connections'].to_i).to be > 0
    end

    it 'handles steps without last_attempted_at correctly' do
      # Get current counts before adding more data
      before_additional = execute_health_counts_function

      # Create additional workflow with error steps without last_attempted_at
      additional_workflow = create(:linear_workflow_task)
      steps = additional_workflow.workflow_steps.limit(2)

      steps.each do |step|
        set_step_to_error(step, 'Test error without backoff')
        step.update!(
          attempts: 1,
          retry_limit: 3,
          retryable: true,
          last_attempted_at: nil
        )
      end

      result = execute_health_counts_function

      # Should have 1 more retryable error (one step gets completed due to dependencies)
      # but no additional backoff steps since we set last_attempted_at to nil
      expect(result['retryable_error_steps'].to_i).to eq(before_additional['retryable_error_steps'].to_i + 1)
      expect(result['in_backoff_steps'].to_i).to eq(before_additional['in_backoff_steps'].to_i) # No change
    end
  end

  describe 'performance characteristics' do
    # Use let to create test data once and reuse it
    let(:completed_workflows) do
      Array.new(10) do
        task = create(:linear_workflow_task)
        task.workflow_steps.each do |step|
          complete_step_via_state_machine(step)
        end
        task
      end
    end

    let(:pending_workflows) do
      create_list(:diamond_workflow_task, 5)
    end

    let(:error_workflows) do
      Array.new(3) do
        task = create(:tree_workflow_task)
        # Add some error steps
        task.workflow_steps.limit(2).each do |step|
          set_step_to_error(step, 'Performance test error')
          step.update!(attempts: 1, retry_limit: 3)
        end
        task
      end
    end

    before do
      # Force evaluation of let variables to create test data
      completed_workflows
      pending_workflows
      error_workflows
    end

    it 'executes in reasonable time' do
      execution_time = Benchmark.realtime do
        10.times { execute_health_counts_function }
      end

      average_time = execution_time / 10
      expect(average_time).to be < 1 # Should average under 1 second
    end
  end

  describe 'data consistency' do
    # Use let to create test data once and reuse it
    let(:consistency_completed_workflows) do
      Array.new(3) do
        task = create(:linear_workflow_task)
        task.workflow_steps.each do |step|
          complete_step_via_state_machine(step)
        end
        task
      end
    end

    let(:consistency_pending_workflows) do
      create_list(:diamond_workflow_task, 2)
    end

    it 'maintains consistency across multiple calls' do
      # Force evaluation of let variables to create test data
      consistency_completed_workflows
      consistency_pending_workflows

      # Execute multiple times
      results = Array.new(3) { execute_health_counts_function }

      # All results should be identical
      first_result = results.first
      results.each do |result|
        expect(result['total_tasks']).to eq(first_result['total_tasks'])
        expect(result['total_steps']).to eq(first_result['total_steps'])
        expect(result['complete_tasks']).to eq(first_result['complete_tasks'])
        expect(result['pending_steps']).to eq(first_result['pending_steps'])
      end
    end
  end

  private

  def execute_health_counts_function
    ActiveRecord::Base.connection.execute('SELECT * FROM get_system_health_counts_v01()').first
  end

  def execute_individual_count_queries
    # Simulate the old approach with multiple queries using proper joins
    {
      total_tasks: Tasker::Task.count,
      pending_tasks: Tasker::Task.joins(:task_transitions)
                                 .where(task_transitions: { most_recent: true, to_state: 'pending' })
                                 .count,
      complete_tasks: Tasker::Task.joins(:task_transitions)
                                  .where(task_transitions: { most_recent: true, to_state: 'complete' })
                                  .count,
      total_steps: Tasker::WorkflowStep.count,
      pending_steps: Tasker::WorkflowStep.joins(:workflow_step_transitions)
                                         .where(workflow_step_transitions: { most_recent: true, to_state: 'pending' })
                                         .count,
      complete_steps: Tasker::WorkflowStep.joins(:workflow_step_transitions)
                                          .where(workflow_step_transitions: { most_recent: true, to_state: 'complete' })
                                          .count,
      error_steps: Tasker::WorkflowStep.joins(:workflow_step_transitions)
                                       .where(workflow_step_transitions: { most_recent: true, to_state: 'error' })
                                       .count
    }
  end
end
