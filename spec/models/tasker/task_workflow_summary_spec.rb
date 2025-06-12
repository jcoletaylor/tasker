# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::TaskWorkflowSummary do
  include FactoryWorkflowHelpers

  describe 'view functionality' do
    it 'returns workflow summary data for a task with workflow steps' do
      # Create a task with steps using our standard factory approach
      # The dummy_task_workflow factory always creates 4 steps: step-one, step-two, step-three, step-four
      task = create_dummy_task_for_orchestration

      # The view should return one record for the task
      summary = described_class.find_by(task_id: task.task_id)

      expect(summary).to be_present
      expect(summary.task_id).to eq(task.task_id)

      # Check that it inherits TaskExecutionContext fields (4 steps in dummy workflow)
      expect(summary.total_steps).to eq(4)
      expect(summary.pending_steps).to be >= 0
      expect(summary.ready_steps).to be >= 0
      expect(summary.completion_percentage).to be_a(Numeric)
      expect(summary.execution_status).to be_present
      expect(summary.recommended_action).to be_present

      # Check TaskWorkflowSummary-specific fields (new view structure)
      expect(summary.ready_step_ids).to be_a(Array)
      expect(summary.workflow_efficiency).to be_present
      expect(summary.parallelism_potential).to be_present
      expect(summary.root_step_ids).to be_a(Array)
      expect(summary.root_step_count).to be >= 0
    end

    it 'provides actionable step IDs for workflow processing' do
      # Create the standard dummy workflow
      task = create_dummy_task_for_orchestration

      summary = described_class.find_by(task_id: task.task_id)

      # For a new workflow, should have ready steps available
      expect(summary.ready_step_ids).not_to be_empty
      expect(summary.ready_steps).to be > 0

      # Should identify root steps correctly (step-one and step-two are independent)
      expect(summary.root_step_ids).not_to be_empty
      expect(summary.root_step_count).to eq(2) # Two root steps in the dummy workflow
    end

    it 'recommends appropriate processing strategies' do
      # Create workflows to test strategy recommendations
      # The dummy workflow always creates 4 steps with 2 ready initially
      task = create_dummy_task_for_orchestration

      summary = described_class.find_by(task_id: task.task_id)

      # Verify workflow insights are provided (new descriptive approach)
      # With 2 ready steps, should show parallelism potential
      expect(summary.workflow_efficiency).to be_in(%w[optimal recovering processing blocked waiting])
      expect(summary.parallelism_potential).to be_in(%w[high_parallelism moderate_parallelism sequential_only no_ready_work])

      # Verify the new view structure provides meaningful insights
      expect(summary.workflow_efficiency).to be_present
      expect(summary.parallelism_potential).to be_present
    end

    it 'maintains read-only model behavior' do
      # Verify this is a read-only model backed by a database view
      summary = described_class.new
      expect(summary.readonly?).to be true
    end
  end
end
