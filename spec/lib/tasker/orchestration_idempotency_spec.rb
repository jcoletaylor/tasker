# frozen_string_literal: true

require 'rails_helper'
require_relative '../../mocks/configurable_failure_handlers'

RSpec.describe 'Orchestration and Idempotency Testing' do
  # Comprehensive tests for workflow orchestration, retry logic, and idempotency
  # Uses the TestCoordinator to bypass ActiveJob and test synchronously

  before(:all) do
    # Register test handlers
    Tasker::HandlerFactory.instance.register(
      ConfigurableFailureTask::TASK_NAME,
      ConfigurableFailureTask
    )

    # Activate test coordination mode
    TestOrchestration::TestCoordinator.activate!
  end

  after(:all) do
    # Clean up and deactivate test mode
    TestOrchestration::TestCoordinator.deactivate!
    Tasker::Testing::IdempotencyTestHandler.clear_execution_registry!
  end

  before do
    # Clear failure patterns and execution logs between tests
    TestOrchestration::TestCoordinator.clear_failure_patterns!
    Tasker::Testing::IdempotencyTestHandler.clear_execution_registry!
  end

  describe 'Test Coordinator functionality' do
    it 'processes tasks synchronously without job queuing' do
      task = create(:linear_workflow_task)

      # Process synchronously
      start_time = Time.current
      result = TestOrchestration::TestCoordinator.process_task_synchronously(task)
      execution_time = Time.current - start_time

      expect(result).to be true
      expect(execution_time).to be < 1.second # Should be fast without job delays

      # Verify task completed
      task.reload
      expect(task.status).to eq(Tasker::Constants::TaskStatuses::COMPLETE)
      expect(task.workflow_steps.all?(&:processed)).to be true
    end

    it 'processes multiple tasks in batch efficiently' do
      tasks = [
        create(:diamond_workflow_task),
        create(:parallel_merge_workflow_task),
        create(:tree_workflow_task)
      ]

      results = TestOrchestration::TestCoordinator.process_tasks_batch(tasks)

      expect(results[:processed]).to eq(3)
      expect(results[:succeeded]).to eq(3)
      expect(results[:failed]).to eq(0)
      expect(results[:execution_time]).to be < 3.seconds

      # Verify all tasks completed
      tasks.each do |task|
        task.reload
        expect(task.status).to eq(Tasker::Constants::TaskStatuses::COMPLETE)
      end
    end

    it 'tracks execution statistics for analysis' do
      task = create(:linear_workflow_task)

      TestOrchestration::TestCoordinator.process_task_synchronously(task)

      stats = TestOrchestration::TestCoordinator.execution_stats
      expect(stats[:total_executions]).to be > 0
      expect(stats[:recent_executions]).to be_an(Array)
      expect(stats[:recent_executions].last[:message]).to include(task.task_id.to_s)
    end
  end

  describe 'Configurable failure handling and retry logic' do
    let(:failure_task_request) do
      Tasker::Types::TaskRequest.new(
        name: ConfigurableFailureTask::TASK_NAME,
        context: { test_scenario: 'retry_testing', batch_id: 'test_batch' },
        initiator: 'test_system',
        reason: 'testing_configurable_failures'
      )
    end

    it 'handles step failures with proper retry logic' do
      # Create task with configurable failure handlers
      task_handler = Tasker::HandlerFactory.instance.get(ConfigurableFailureTask::TASK_NAME)
      task = task_handler.initialize_task!(failure_task_request)

      # Process task - should handle retries automatically
      result = TestOrchestration::TestCoordinator.process_task_synchronously(task)
      expect(result).to be true

      task.reload

      # Verify reliable step succeeded immediately
      reliable_step = task.workflow_steps.joins(:named_step)
                          .find_by(named_step: { name: ConfigurableFailureTask::RELIABLE_STEP })
      expect(reliable_step.attempts).to eq(1)
      expect(reliable_step.status).to eq('complete')

      # Verify flaky step eventually succeeded after retries
      flaky_step = task.workflow_steps.joins(:named_step)
                       .find_by(named_step: { name: ConfigurableFailureTask::FLAKY_STEP })
      expect(flaky_step.attempts).to be > 1 # Should have retried
      expect(flaky_step.status).to eq('complete')
      expect(flaky_step.results['failed_attempts']).to be > 0
    end

    it 'respects retry limits and fails appropriately' do
      # Configure a step to fail more times than the retry limit allows
      TestOrchestration::TestCoordinator.configure_step_failure(
        ConfigurableFailureTask::RELIABLE_STEP,
        failure_count: 5, # More than default retry limit
        failure_message: 'Exceeds retry limit'
      )

      task_handler = Tasker::HandlerFactory.instance.get(ConfigurableFailureTask::TASK_NAME)
      task = task_handler.initialize_task!(failure_task_request)

      # Process task - should fail due to retry limit
      result = TestOrchestration::TestCoordinator.process_task_synchronously(task)
      expect(result).to be false # Task should fail

      task.reload

      # Verify task failed due to step exceeding retry limit
      reliable_step = task.workflow_steps.joins(:named_step)
                          .find_by(named_step: { name: ConfigurableFailureTask::RELIABLE_STEP })
      expect(reliable_step.attempts).to be >= reliable_step.retry_limit
      expect(reliable_step.status).to eq('failed')
    end

    it 'tracks retry patterns for analysis' do
      # Configure specific failure patterns
      TestOrchestration::TestCoordinator.configure_step_failure(
        ConfigurableFailureTask::FLAKY_STEP,
        failure_count: 2
      )

      task_handler = Tasker::HandlerFactory.instance.get(ConfigurableFailureTask::TASK_NAME)
      task = task_handler.initialize_task!(failure_task_request)

      TestOrchestration::TestCoordinator.process_task_synchronously(task)

      stats = TestOrchestration::TestCoordinator.execution_stats
      expect(stats[:retry_tracking]).to have_key(ConfigurableFailureTask::FLAKY_STEP)
      expect(stats[:retry_tracking][ConfigurableFailureTask::FLAKY_STEP]).to be > 0
    end
  end

  describe 'Idempotency testing through re-execution' do
    let(:idempotent_task_request) do
      Tasker::Types::TaskRequest.new(
        name: ConfigurableFailureTask::TASK_NAME,
        context: { test_scenario: 'idempotency_testing', batch_id: 'idempotent_batch' },
        initiator: 'test_system',
        reason: 'testing_idempotency'
      )
    end

    it 'produces identical results on re-execution (idempotent behavior)' do
      task_handler = Tasker::HandlerFactory.instance.get(ConfigurableFailureTask::TASK_NAME)
      task = task_handler.initialize_task!(idempotent_task_request)

      # First execution
      result1 = TestOrchestration::TestCoordinator.process_task_synchronously(task)
      expect(result1).to be true

      task.reload
      first_execution_results = task.workflow_steps.map do |step|
        { step_name: step.name, results: step.results }
      end

      # Re-execute for idempotency test
      TestOrchestration::TestCoordinator.reenqueue_for_idempotency_test([task], reset_steps: true)

      task.reload
      second_execution_results = task.workflow_steps.map do |step|
        { step_name: step.name, results: step.results }
      end

      # Verify idempotency - core data should be the same
      first_execution_results.each do |first_result|
        second_result = second_execution_results.find { |r| r[:step_name] == first_result[:step_name] }

        # For idempotent step, check that deterministic data matches
        next unless first_result[:step_name] == ConfigurableFailureTask::IDEMPOTENT_STEP

        expect(second_result[:results]['checksum']).to eq(first_result[:results]['checksum'])
        expect(second_result[:results]['sequence_number']).to eq(first_result[:results]['sequence_number'])
        expect(second_result[:results]['idempotency_check']['is_repeat_execution']).to be true
      end
    end

    it 'tracks execution counts correctly across re-executions' do
      task_handler = Tasker::HandlerFactory.instance.get(ConfigurableFailureTask::TASK_NAME)
      task = task_handler.initialize_task!(idempotent_task_request)

      # Execute multiple times
      3.times do
        TestOrchestration::TestCoordinator.process_task_synchronously(task)
        TestOrchestration::TestCoordinator.reenqueue_for_idempotency_test([task], reset_steps: true)
      end

      # Check execution tracking
      stats = Tasker::Testing::IdempotencyTestHandler.execution_stats
      idempotent_key = "#{task.task_id}_#{ConfigurableFailureTask::IDEMPOTENT_STEP}"

      expect(stats).to have_key(idempotent_key)
      expect(stats[idempotent_key][:execution_count]).to be >= 3
    end

    it 'maintains data integrity across reset and re-execution cycles' do
      task = create(:diamond_workflow_task)

      # Complete the task initially
      result1 = TestOrchestration::TestCoordinator.process_task_synchronously(task)
      expect(result1).to be true

      task.reload
      initial_step_count = task.workflow_steps.count
      initial_edge_count = task.workflow_steps.joins(:to_edges).count

      # Reset and re-execute
      TestOrchestration::TestCoordinator.reenqueue_for_idempotency_test([task], reset_steps: true)

      task.reload

      # Verify structural integrity is maintained
      expect(task.workflow_steps.count).to eq(initial_step_count)
      expect(task.workflow_steps.joins(:to_edges).count).to eq(initial_edge_count)

      # Verify all steps are back to pending state
      expect(task.workflow_steps.all? { |s| s.status == 'pending' }).to be true
      expect(task.workflow_steps.all? { |s| !s.processed }).to be true
    end
  end

  describe 'Large scale orchestration testing' do
    it 'processes large batches of complex workflows efficiently' do
      # Create a mix of workflow patterns
      tasks = []

      # 5 of each pattern type
      factory_map = {
        linear_workflow: :linear_workflow_task,
        diamond_workflow: :diamond_workflow_task,
        parallel_merge_workflow: :parallel_merge_workflow_task,
        tree_workflow: :tree_workflow_task
      }

      factory_map.each do |pattern, factory_name|
        5.times do |i|
          tasks << create(factory_name,
                          context: { batch_id: "large_scale_#{i}", pattern: pattern })
        end
      end

      # Process all tasks in batch
      start_time = Time.current
      results = TestOrchestration::TestCoordinator.process_tasks_batch(tasks)
      total_time = Time.current - start_time

      # Verify performance and success
      expect(results[:processed]).to eq(20)
      expect(results[:succeeded]).to eq(20)
      expect(results[:failed]).to eq(0)
      expect(total_time).to be < 10.seconds # Should complete within reasonable time

      # Verify all workflows completed successfully
      tasks.each do |task|
        task.reload
        expect(task.status).to eq(Tasker::Constants::TaskStatuses::COMPLETE)
        expect(task.workflow_steps.all?(&:processed)).to be true
      end
    end

    it 'handles mixed success/failure scenarios in large batches' do
      # Create tasks with different failure configurations
      reliable_tasks = create_list(:linear_workflow_task, 3)

      # Configure some tasks to have failures
      flaky_tasks = Array.new(2) do |i|
        create(:diamond_workflow_task,
               context: { test_scenario: 'mixed_batch', index: i })
      end

      # Configure failure for diamond workflows
      TestOrchestration::TestCoordinator.configure_step_failure(
        'process_a',
        failure_count: 1,
        failure_message: 'Transient failure'
      )

      all_tasks = reliable_tasks + flaky_tasks
      results = TestOrchestration::TestCoordinator.process_tasks_batch(all_tasks)

      # Should handle mixed scenarios appropriately
      expect(results[:processed]).to eq(5)
      expect(results[:succeeded]).to be >= 3 # At least the reliable tasks

      # Verify execution statistics
      stats = TestOrchestration::TestCoordinator.execution_stats
      expect(stats[:total_executions]).to be >= 5
    end
  end

  describe 'Error handling and recovery patterns' do
    it 'handles step handler exceptions gracefully' do
      # Configure a step to always fail
      TestOrchestration::TestCoordinator.configure_step_failure(
        ConfigurableFailureTask::RELIABLE_STEP,
        failure_count: 10, # Always fails
        failure_message: 'Permanent failure for testing'
      )

      task_handler = Tasker::HandlerFactory.instance.get(ConfigurableFailureTask::TASK_NAME)
      task_request = Tasker::Types::TaskRequest.new(
        name: ConfigurableFailureTask::TASK_NAME,
        context: { test_scenario: 'error_handling' },
        initiator: 'test_system',
        reason: 'testing_error_handling'
      )

      task = task_handler.initialize_task!(task_request)

      # Should handle the failure gracefully
      expect do
        TestOrchestration::TestCoordinator.process_task_synchronously(task)
      end.not_to raise_error

      # Verify appropriate error state
      task.reload
      expect(task.status).to eq(Tasker::Constants::TaskStatuses::ERROR)

      failed_step = task.workflow_steps.joins(:named_step)
                        .find_by(named_step: { name: ConfigurableFailureTask::RELIABLE_STEP })
      expect(failed_step.status).to eq('failed')
      expect(failed_step.results['error']).to include('Permanent failure for testing')
    end

    it 'maintains workflow integrity during partial failures' do
      task = create(:tree_workflow_task)

      # Configure one branch to fail - use correct step name
      root_step = task.workflow_steps.joins(:named_step)
                      .find_by(named_step: { name: 'root_initialization' })

      # Skip test if step not found (graceful degradation)
      skip 'Root step not found in tree workflow' unless root_step

      # Use safe transitions to avoid state machine errors
      # Include IdempotentStateTransitions concern for safe_transition_to
      extend Tasker::Concerns::IdempotentStateTransitions

      # Manually fail the root step to test dependency handling
      safe_transition_to(root_step, Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS)
      safe_transition_to(root_step, Tasker::Constants::WorkflowStepStatuses::ERROR)
      root_step.update_columns(
        attempts: root_step.retry_limit + 1,
        results: { error: 'Root step failure' }
      )

      # Try to process - should handle the failure gracefully
      result = TestOrchestration::TestCoordinator.process_task_synchronously(task)
      expect(result).to be false # Should fail due to root step failure

      task.reload

      # Verify dependent steps weren't processed (due to failed dependency)
      dependent_steps = task.workflow_steps.joins(:outgoing_edges)
                            .where(tasker_workflow_step_edges: { from_step_id: root_step.workflow_step_id })

      dependent_steps.each do |step|
        # Dependent steps may be in error state due to failed dependency
        # or remain pending if they haven't been processed yet
        expect(step.status).to be_in(['pending', 'error'])
      end
    end
  end
end
