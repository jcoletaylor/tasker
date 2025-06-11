# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Workflow Testing Infrastructure Demo', :integration do
  # Demonstration of the comprehensive workflow testing infrastructure
  # Shows how to use complex factories, test coordination, and analysis helpers

  before(:all) do
    # This demo creates substantial test data - clean up before starting
    Tasker::Task.destroy_all
  end

  after(:all) do
    # Clean up after demo
    Tasker::Task.destroy_all
  end

  describe 'Large Dataset Creation and Database View Testing' do
    it 'creates complex workflows with various DAG patterns and tests database views' do
      # Create a diverse dataset of 30 workflows with different patterns
      workflows = create_diverse_workflow_dataset(count: 30)

      # Verify we created the expected variety
      expect(workflows.count).to eq(30)
      patterns = workflows.map { |w| w.context['pattern'] }.uniq
      expect(patterns.count).to be >= 4 # Should have multiple different patterns

      # Test that database views handle the large dataset correctly
      view_performance = benchmark_database_views(task_count: workflows.count, workflows: workflows)

      # Verify reasonable performance (adjust thresholds as needed)
      expect(view_performance[:task_workflow_summary][:execution_time]).to be < 3.seconds
      expect(view_performance[:step_readiness_status][:execution_time]).to be < 3.seconds
      expect(view_performance[:step_dag_relationships][:execution_time]).to be < 3.seconds

      # Verify correct record counts
      expect(view_performance[:task_workflow_summary][:record_count]).to eq(30)
      expect(view_performance[:step_readiness_status][:record_count]).to be > 150 # ~6+ steps per task
      expect(view_performance[:step_dag_relationships][:record_count]).to be > 150

      puts "\n=== Database View Performance Results ==="
      view_performance.each do |view_name, metrics|
        puts "#{view_name}: #{metrics[:execution_time].round(3)}s, #{metrics[:record_count]} records"
      end
    end

    it 'verifies database view accuracy with complex DAG relationships' do
      # Create specific workflows with known structures
      diamond_task = create(:diamond_workflow_task)
      tree_task = create(:tree_workflow_task)
      mixed_task = create(:mixed_workflow_task)

      # Test DAG relationship view accuracy
      diamond_dag = Tasker::StepDagRelationship.where(task_id: diamond_task.task_id)

      # Diamond workflow should have exactly 1 root step
      root_steps = diamond_dag.where(is_root_step: true)
      expect(root_steps.count).to eq(1)

      # Should have at least one leaf step
      leaf_steps = diamond_dag.where(is_leaf_step: true)
      expect(leaf_steps.count).to be >= 1

      # Test readiness calculation
      readiness_statuses = Tasker::StepReadinessStatus.where(task_id: diamond_task.task_id)

      # Root steps should be ready (no dependencies)
      root_ready = readiness_statuses.where(total_parents: 0)
      expect(root_ready.all?(&:ready_for_execution)).to be true

      puts "\n=== DAG Structure Analysis ==="
      puts "Diamond workflow: #{diamond_dag.count} steps, #{root_steps.count} roots, #{leaf_steps.count} leaves"
      puts "Tree workflow: #{Tasker::StepDagRelationship.where(task_id: tree_task.task_id).count} steps"
      puts "Mixed workflow: #{Tasker::StepDagRelationship.where(task_id: mixed_task.task_id).count} steps"
    end
  end

  describe 'Test Coordinator and Synchronous Processing' do
    it 'processes workflows synchronously without ActiveJob queuing' do
      # Setup test coordination
      setup_test_coordination

      begin
        # Create workflows to process
        workflows = [
          create(:linear_workflow_task),
          create(:diamond_workflow_task),
          create(:parallel_merge_workflow_task)
        ]

        # Process with detailed metrics
        metrics = process_workflows_with_metrics(workflows)

        # Verify successful processing
        expect(metrics[:successful_workflows]).to eq(3)
        expect(metrics[:failed_workflows]).to eq(0)
        expect(metrics[:total_execution_time]).to be < 5.seconds

        # Verify all workflows completed
        workflows.each do |workflow|
          workflow.reload
          expect(workflow.status).to eq(Tasker::Constants::TaskStatuses::COMPLETE)
          expect(workflow.workflow_steps.all?(&:processed)).to be true
        end

        puts "\n=== Orchestration Performance Metrics ==="
        puts "Total workflows: #{metrics[:total_workflows]}"
        puts "Successful: #{metrics[:successful_workflows]}"
        puts "Total execution time: #{metrics[:total_execution_time].round(3)}s"
        puts "Average per workflow: #{metrics[:average_execution_time].round(3)}s"
        puts "Total steps processed: #{metrics[:total_steps_processed]}"
      ensure
        cleanup_test_coordination
      end
    end

    it 'handles configurable failure scenarios for testing retry logic' do
      setup_test_coordination(configure_failures: {
                                'flaky_step' => { failure_count: 2, failure_message: 'Simulated network timeout' },
                                'process_a' => { failure_count: 1, failure_message: 'Transient API error' }
                              })

      begin
        # Create workflows with failure scenarios
        failure_workflows = create_failure_test_workflows

        # Process and analyze results
        metrics = process_workflows_with_metrics(failure_workflows)

        # Should handle most scenarios successfully (some may fail by design)
        expect(metrics[:successful_workflows]).to be >= 2

        # Verify retry tracking
        coordinator_stats = Tasker::Orchestration::TestCoordinator.execution_stats
        expect(coordinator_stats[:retry_tracking]).to be_present

        puts "\n=== Failure Scenario Testing ==="
        puts "Workflows processed: #{metrics[:total_workflows]}"
        puts "Successful with retries: #{metrics[:successful_workflows]}"
        puts "Failed scenarios: #{metrics[:failed_workflows]}"
        puts "Retry patterns tracked: #{coordinator_stats[:retry_tracking].keys}"
      ensure
        cleanup_test_coordination
      end
    end
  end

  describe 'Idempotency Testing' do
    it 'verifies idempotent behavior through re-execution' do
      setup_test_coordination

      begin
        # Test idempotency with multiple re-executions
        idempotency_results = test_workflow_idempotency(re_execution_count: 3)

        # Verify all executions were successful
        expect(idempotency_results[:all_executions_successful]).to be true
        expect(idempotency_results[:total_executions]).to eq(4) # Original + 3 re-executions

        # Should have no idempotency violations
        expect(idempotency_results[:idempotency_violations]).to be_empty

        # Verify execution tracking
        handler_stats = idempotency_results[:handler_execution_stats]
        expect(handler_stats).to be_present

        puts "\n=== Idempotency Test Results ==="
        puts "Total executions: #{idempotency_results[:total_executions]}"
        puts "All successful: #{idempotency_results[:all_executions_successful]}"
        puts "Idempotency violations: #{idempotency_results[:idempotency_violations].count}"
        puts "Handler execution tracking: #{handler_stats.keys.count} steps tracked"
      ensure
        cleanup_test_coordination
      end
    end
  end

  describe 'Comprehensive Testing Infrastructure Demo' do
    it 'generates a complete workflow testing report' do
      # Generate comprehensive test report with all features
      report = generate_workflow_test_report(
        dataset_size: 15, # Smaller for demo to keep test time reasonable
        include_performance: true,
        include_idempotency: true,
        include_failure_scenarios: true,
        re_execution_count: 2
      )

      # Verify report structure and completeness
      expect(report[:test_timestamp]).to be_present
      expect(report[:test_configuration]).to be_present
      expect(report[:results]).to be_present

      results = report[:results]

      # Verify all test categories were included
      expect(results[:database_view_performance]).to be_present
      expect(results[:orchestration_performance]).to be_present
      expect(results[:failure_scenario_performance]).to be_present
      expect(results[:idempotency_analysis]).to be_present
      expect(results[:summary]).to be_present

      # Verify meaningful data in each category
      expect(results[:database_view_performance]).to have_key(:task_workflow_summary)
      expect(results[:orchestration_performance][:total_workflows]).to eq(15)
      expect(results[:idempotency_analysis][:total_executions]).to be >= 3

      puts "\n=== COMPREHENSIVE WORKFLOW TESTING REPORT ==="
      puts "Test timestamp: #{report[:test_timestamp]}"
      puts "Dataset size: #{report[:test_configuration][:dataset_size]}"
      puts "\n--- Database View Performance ---"
      results[:database_view_performance].each do |view, metrics|
        puts "  #{view}: #{metrics[:execution_time].round(3)}s (#{metrics[:record_count]} records)"
      end

      puts "\n--- Orchestration Performance ---"
      orch = results[:orchestration_performance]
      puts "  Workflows: #{orch[:total_workflows]} (#{orch[:successful_workflows]} successful)"
      puts "  Execution time: #{orch[:total_execution_time].round(3)}s"
      puts "  Steps processed: #{orch[:total_steps_processed]}"

      puts "\n--- Failure Scenarios ---"
      failure = results[:failure_scenario_performance]
      puts "  Scenarios tested: #{failure[:total_workflows]}"
      puts "  Successful recoveries: #{failure[:successful_workflows]}"

      puts "\n--- Idempotency Analysis ---"
      idem = results[:idempotency_analysis]
      puts "  Executions: #{idem[:total_executions]}"
      puts "  All successful: #{idem[:all_executions_successful]}"
      puts "  Violations: #{idem[:idempotency_violations].count}"

      puts "\n--- Summary ---"
      summary = results[:summary]
      puts "  Total workflows created: #{summary[:total_workflows_created]}"
      puts "  Total steps created: #{summary[:total_steps_created]}"
      puts "  Test coordinator active: #{summary[:test_coordinator_active]}"

      puts "\n=== REPORT COMPLETE ==="
    end
  end

  describe 'Real-world Scenario Simulation' do
    it 'simulates a production-like workload with mixed patterns and states' do
      # Simulate a production environment with:
      # - Multiple workflow patterns running concurrently
      # - Some workflows in various completion states
      # - Occasional failures and retries
      # - Re-enqueuing scenarios

      setup_test_coordination(configure_failures: {
                                # Simulate network timeouts in 10% of workflows
                                'fetch_data' => { failure_count: 1, failure_message: 'Network timeout' }
                              })

      begin
        # Create a realistic mix of workflows
        production_workflows = []

        # 10 currently running workflows (various patterns)
        5.times { production_workflows << create(:diamond_workflow_task) }
        3.times { production_workflows << create(:tree_workflow_task) }
        2.times { production_workflows << create(:mixed_workflow_task) }

        # Process the initial batch
        initial_metrics = process_workflows_with_metrics(production_workflows)

        # Simulate some workflows being re-enqueued (e.g., after system restart)
        workflows_to_reenqueue = production_workflows.sample(3)
        TestOrchestration::TestCoordinator.reenqueue_for_idempotency_test(
          workflows_to_reenqueue,
          reset_steps: true
        )

        # Process re-enqueued workflows
        reenqueue_metrics = process_workflows_with_metrics(workflows_to_reenqueue)

        # Verify production-like behavior
        total_successful = initial_metrics[:successful_workflows] + reenqueue_metrics[:successful_workflows]
        expect(total_successful).to be >= 10 # Most should succeed

        # Verify database views handle the mixed states correctly
        final_summaries = Tasker::TaskWorkflowSummary.where(
          task_id: production_workflows.map(&:task_id)
        )

        expect(final_summaries.count).to eq(10)

        # Should have a mix of processing strategies
        strategies = final_summaries.map(&:processing_strategy).uniq
        expect(strategies.count).to be >= 2

        puts "\n=== Production Workload Simulation ==="
        puts "Initial batch: #{initial_metrics[:successful_workflows]}/#{initial_metrics[:total_workflows]} successful"
        puts "Re-enqueued: #{reenqueue_metrics[:successful_workflows]}/#{reenqueue_metrics[:total_workflows]} successful"
        puts "Processing strategies observed: #{strategies}"
        puts "Total execution time: #{(initial_metrics[:total_execution_time] + reenqueue_metrics[:total_execution_time]).round(3)}s"

        # Verify coordinator tracked the complexity appropriately
        coordinator_stats = Tasker::Orchestration::TestCoordinator.execution_stats
        puts "Coordinator executions logged: #{coordinator_stats[:total_executions]}"
      ensure
        cleanup_test_coordination
      end
    end
  end
end
