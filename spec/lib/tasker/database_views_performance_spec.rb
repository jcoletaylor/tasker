# frozen_string_literal: true

require 'rails_helper'
require_relative '../../mocks/configurable_failure_handlers'

RSpec.describe 'Database Views Performance with Large Datasets' do
  # Test the database views with complex workflows and large datasets
  # This validates that the SQL views perform correctly under realistic loads

  before(:all) do
    # Clean up any existing test data
    Tasker::Task.destroy_all

    # Register configurable failure task handler
    Tasker::HandlerFactory.instance.register(
      ConfigurableFailureTask::TASK_NAME,
      ConfigurableFailureTask
    )
  end

  after(:all) do
    # Clean up test data
    Tasker::Task.destroy_all
    Tasker::Testing::IdempotencyTestHandler.clear_execution_registry!
  end

  describe 'TaskWorkflowSummary view with complex workflows' do
    let!(:workflow_dataset) { build(:workflow_dataset, task_count: 20) }

    it 'correctly aggregates task and step counts across multiple workflow patterns' do
      # Verify we have the expected number of tasks
      expect(Tasker::Task.count).to eq(20)

      # Query the view for all tasks
      summaries = Tasker::TaskWorkflowSummary.all
      expect(summaries.count).to eq(20)

      # Verify aggregation accuracy
      summaries.each do |summary|
        task = Tasker::Task.find(summary.task_id)

        # Verify step counts match actual data
        actual_total = task.workflow_steps.count
        task.workflow_steps.joins(:workflow_step_transitions)
            .where(workflow_step_transitions: {
                     to_state: 'pending',
                     most_recent: true
                   }).count
        actual_completed = task.workflow_steps.joins(:workflow_step_transitions)
                               .where(workflow_step_transitions: {
                                        to_state: 'complete',
                                        most_recent: true
                                      }).count

        expect(summary.total_steps).to eq(actual_total)
        expect(summary.pending_steps + summary.completed_steps + summary.failed_steps).to eq(actual_total)

        # Verify completion percentage calculation
        expected_percentage = actual_total > 0 ? (actual_completed.to_f / actual_total * 100).round(2) : 0
        expect(summary.completion_percentage).to be_within(0.1).of(expected_percentage)
      end
    end

    it 'correctly identifies processing strategies for different workflow sizes' do
      summaries = Tasker::TaskWorkflowSummary.includes(:task).all

      summaries.each do |summary|
        case summary.ready_steps
        when 0
          expect(summary.processing_strategy).to eq('waiting')
        when 1
          expect(summary.processing_strategy).to eq('sequential')
        when 2..5
          expect(summary.processing_strategy).to eq('small_parallel')
        else
          expect(summary.processing_strategy).to eq('batch_parallel')
        end
      end
    end

    it 'provides actionable next_executable_step_ids for workflow orchestration' do
      summaries = Tasker::TaskWorkflowSummary.where('ready_steps > 0')

      summaries.each do |summary|
        step_ids = summary.next_executable_step_ids
        expect(step_ids).to be_an(Array)
        expect(step_ids.size).to eq(summary.ready_steps)

        # Verify all returned step IDs are actually ready for execution
        ready_steps = Tasker::StepReadinessStatus.where(
          task_id: summary.task_id,
          ready_for_execution: true
        )
        expect(step_ids.sort).to eq(ready_steps.pluck(:workflow_step_id).sort)
      end
    end
  end

  describe 'StepReadinessStatus view with complex DAG relationships' do
    let!(:diamond_workflow) { create(:diamond_workflow_task) }
    let!(:tree_workflow) { create(:tree_workflow_task) }
    let!(:mixed_workflow) { create(:mixed_workflow_task) }

    it 'correctly calculates dependency satisfaction across complex DAGs' do
      # Test diamond workflow dependencies
      diamond_steps = Tasker::StepReadinessStatus.where(task_id: diamond_workflow.task_id)

      diamond_steps.each do |step_status|
        step = Tasker::WorkflowStep.find(step_status.workflow_step_id)
        actual_parents = step.parents.count
        completed_parents = step.parents.joins(:workflow_step_transitions)
                                .where(workflow_step_transitions: {
                                         to_state: %w[complete resolved_manually],
                                         most_recent: true
                                       }).count

        expect(step_status.total_parents).to eq(actual_parents)
        expect(step_status.completed_parents).to eq(completed_parents)

        expected_satisfaction = actual_parents == 0 || completed_parents == actual_parents
        expect(step_status.dependencies_satisfied).to eq(expected_satisfaction)
      end
    end

    it 'correctly identifies ready steps in tree structures' do
      tree_steps = Tasker::StepReadinessStatus.where(task_id: tree_workflow.task_id)

      # Root step should be ready (no dependencies)
      root_steps = tree_steps.where(total_parents: 0)
      expect(root_steps.all?(&:ready_for_execution)).to be true

      # Steps with incomplete dependencies should not be ready
      dependent_steps = tree_steps.where('total_parents > completed_parents')
      dependent_steps.each do |step_status|
        expect(step_status.ready_for_execution).to be false
      end
    end

    it 'handles retry logic correctly for failed steps' do
      failed_steps = Tasker::StepReadinessStatus.joins(:workflow_step)
                                                .where(task_id: tree_workflow.task_id)
                                                .where(current_state: 'failed')

      failed_steps.each do |step_status|
        step = step_status.workflow_step

        # Check retry eligibility based on attempts and limits
        if step.attempts >= step.retry_limit
          expect(step_status.retry_eligible).to be false
        else
          # Should be eligible if within retry limits and backoff period passed
          expect(step_status.retry_eligible).to be true
        end
      end
    end
  end

  describe 'StepDAGRelationships view with complex hierarchies' do
    let!(:large_tree) { create(:tree_workflow_task) }
    let!(:complex_mixed) { create(:mixed_workflow_task) }

    it 'correctly identifies root and leaf steps in complex hierarchies' do
      tree_dag = Tasker::StepDagRelationship.where(task_id: large_tree.task_id)

      # Should have exactly one root step
      root_steps = tree_dag.where(is_root_step: true)
      expect(root_steps.count).to eq(1)

      # Root step should have 0 parents
      root_step = root_steps.first
      expect(root_step.parent_count).to eq(0)
      expect(root_step.parent_step_ids).to eq([])

      # Should have at least one leaf step
      leaf_steps = tree_dag.where(is_leaf_step: true)
      expect(leaf_steps.count).to be >= 1

      # Leaf steps should have 0 children
      leaf_steps.each do |leaf|
        expect(leaf.child_count).to eq(0)
        expect(leaf.child_step_ids).to eq([])
      end
    end

    it 'calculates depth from root correctly' do
      mixed_dag = Tasker::StepDagRelationship.where(task_id: complex_mixed.task_id)

      # Verify depth calculation makes sense
      mixed_dag.each do |step_dag|
        if step_dag.is_root_step
          expect(step_dag.min_depth_from_root).to eq(0)
        else
          # Non-root steps should have depth > 0
          expect(step_dag.min_depth_from_root).to be > 0
        end
      end

      # Verify depth progression makes sense in the DAG
      max_depth = mixed_dag.maximum(:min_depth_from_root)
      expect(max_depth).to be >= 0
      expect(max_depth).to be <= 10 # Reasonable maximum for our test DAG
    end

    it 'maintains referential integrity in parent/child relationships' do
      all_dags = Tasker::StepDagRelationship.where(task_id: [large_tree.task_id, complex_mixed.task_id])

      all_dags.each do |dag_entry|
        # Verify parent-child relationship symmetry
        dag_entry.parent_step_ids.each do |parent_id|
          parent_dag = all_dags.find_by(workflow_step_id: parent_id)
          expect(parent_dag.child_step_ids).to include(dag_entry.workflow_step_id)
        end

        dag_entry.child_step_ids.each do |child_id|
          child_dag = all_dags.find_by(workflow_step_id: child_id)
          expect(child_dag.parent_step_ids).to include(dag_entry.workflow_step_id)
        end
      end
    end
  end

  describe 'Performance characteristics with large datasets' do
    let!(:large_dataset) { build(:workflow_dataset, task_count: 50) }

    it 'maintains reasonable query performance with 50+ tasks' do
      # Measure query performance for the main views
      start_time = Time.current

      # Query all workflow summaries
      summaries = Tasker::TaskWorkflowSummary.all.to_a
      summary_time = Time.current - start_time

      # Query all step readiness statuses
      start_time = Time.current
      readiness_statuses = Tasker::StepReadinessStatus.all.to_a
      readiness_time = Time.current - start_time

      # Query all DAG relationships
      start_time = Time.current
      dag_relationships = Tasker::StepDagRelationship.all.to_a
      dag_time = Time.current - start_time

      # Performance assertions (these thresholds may need adjustment based on hardware)
      expect(summary_time).to be < 2.seconds
      expect(readiness_time).to be < 2.seconds
      expect(dag_time).to be < 2.seconds

      # Verify we got reasonable result counts
      expect(summaries.count).to eq(50)
      expect(readiness_statuses.count).to be > 200 # ~6 steps per task
      expect(dag_relationships.count).to be > 200

      Rails.logger.info "Performance metrics - Summary: #{summary_time}s, Readiness: #{readiness_time}s, DAG: #{dag_time}s"
    end

    it 'correctly aggregates data across all workflow patterns' do
      # Verify that different workflow patterns are represented
      summaries = Tasker::TaskWorkflowSummary.includes(:task).all

      patterns = summaries.filter_map { |s| s.task.context['pattern'] }.uniq
      expect(patterns.size).to be >= 4 # Should have multiple different patterns

      # Verify reasonable distribution of step counts
      step_counts = summaries.map(&:total_steps)
      expect(step_counts.min).to be >= 6
      expect(step_counts.max).to be <= 12

      # Verify processing strategies are distributed
      strategies = summaries.map(&:processing_strategy).uniq
      expect(strategies).to include('sequential', 'small_parallel')
    end
  end

  describe 'Database view consistency under concurrent access' do
    it 'maintains data consistency when tasks are modified concurrently' do
      # Create a baseline dataset
      task = create(:diamond_workflow_task)

      # Get initial view state
      initial_summary = Tasker::TaskWorkflowSummary.find_by(task_id: task.task_id)
      initial_readiness = Tasker::StepReadinessStatus.where(task_id: task.task_id).to_a

      # Simulate concurrent modifications
      step_to_complete = task.workflow_steps.joins(:named_step)
                             .find_by(named_step: { name: 'start_workflow' })

      # Complete a step
      step_to_complete.state_machine.transition_to!(:in_progress)
      step_to_complete.state_machine.transition_to!(:complete)
      step_to_complete.update_columns(processed: true, processed_at: Time.current)

      # Verify views reflect the changes
      updated_summary = Tasker::TaskWorkflowSummary.find_by(task_id: task.task_id)
      updated_readiness = Tasker::StepReadinessStatus.where(task_id: task.task_id).to_a

      # Summary should show one more completed step
      expect(updated_summary.completed_steps).to eq(initial_summary.completed_steps + 1)
      expect(updated_summary.pending_steps).to eq(initial_summary.pending_steps - 1)

      # Readiness should reflect dependency changes
      expect(updated_readiness.count(&:ready_for_execution)).to be >=
                                                                initial_readiness.count(&:ready_for_execution)
    end
  end
end
