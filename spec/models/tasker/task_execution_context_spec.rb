# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::TaskExecutionContext do
  include FactoryWorkflowHelpers

  describe 'view functionality' do
    it 'returns execution context data for a task with workflow steps' do
      # Create a task with steps using our standard factory approach
      # The dummy_task_workflow factory always creates 4 steps: step-one, step-two, step-three, step-four
      task = create_dummy_task_for_orchestration

      # The view should return a single record for the task
      context = described_class.find_by(task_id: task.task_id)

      expect(context).to be_present
      expect(context.task_id).to eq(task.task_id)

      # Should have execution context fields (using correct column names from view)
      expect(context.total_steps).to eq(4) # Our dummy workflow has 4 steps
      expect(context).to respond_to(:ready_steps)
      expect(context).to respond_to(:in_progress_steps)
      expect(context).to respond_to(:completed_steps)
      expect(context).to respond_to(:failed_steps)
      expect(context).to respond_to(:pending_steps)
      expect(context.execution_status).to be_present
      expect(context.recommended_action).to be_present
    end

    it 'correctly calculates step statistics for pending workflow' do
      # Test the statistics are reasonable for our dummy workflow structure
      task = create_dummy_task_for_orchestration

      context = described_class.find_by(task_id: task.task_id)

      # Basic sanity checks on counts (using correct column names)
      expect(context.total_steps).to eq(4)

      # All step counts should sum to total (each step is in exactly one state)
      step_count_sum = context.pending_steps + context.in_progress_steps + context.completed_steps + context.failed_steps
      expect(step_count_sum).to eq(context.total_steps)

      # For a newly created workflow, we should have:
      # - Some ready steps (the root steps: step-one, step-two)
      # - All steps pending initially
      # - Zero in_progress steps (none started yet)
      # - Zero completed steps (none finished yet)
      # - Zero failed steps (none failed yet)
      expect(context.pending_steps).to eq(4) # All steps start as pending
      expect(context.ready_steps).to eq(2)   # Root steps are ready
      expect(context.in_progress_steps).to eq(0)
      expect(context.completed_steps).to eq(0)
      expect(context.failed_steps).to eq(0)
    end

    it 'provides meaningful execution status and recommendations' do
      task = create_dummy_task_for_orchestration

      context = described_class.find_by(task_id: task.task_id)

      # Execution status should be one of the valid enum values
      expect(Tasker::Constants::VALID_TASK_EXECUTION_STATUSES).to include(context.execution_status)

      # Recommended action should be one of the valid enum values
      expect(Tasker::Constants::VALID_TASK_RECOMMENDED_ACTIONS).to include(context.recommended_action)

      # Health status should be one of the valid enum values (if present)
      if context.respond_to?(:health_status) && context.health_status.present?
        expect(Tasker::Constants::VALID_TASK_HEALTH_STATUSES).to include(context.health_status)
      end

      # For a new workflow with ready steps, we expect specific recommendations
      expect(context.execution_status).to eq('has_ready_steps')
      expect(context.recommended_action).to eq('execute_ready_steps')
      expect(context.health_status).to eq('healthy')

      # Completion percentage should be 0 for new workflow
      expect(context.completion_percentage).to eq(0.0)
    end
  end
end
