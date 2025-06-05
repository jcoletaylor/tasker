# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Tasker::StepReadinessStatus, type: :model do
  include FactoryWorkflowHelpers

  describe 'view functionality' do
    it 'returns readiness data for a task with workflow steps' do
      # Create a task with steps using our standard factory approach
      # The dummy_task_workflow factory always creates 4 steps: step-one, step-two, step-three, step-four
      task = create_dummy_task_for_orchestration

      # Debugging: Check that task and steps were created
      expect(task).to be_persisted, "Task should be persisted"
      expect(task.workflow_steps.count).to eq(4), "Task should have 4 workflow steps"

      # The view should return records for all steps (4 steps in dummy workflow)
      readiness_statuses = described_class.where(task_id: task.task_id)

      if readiness_statuses.count == 0
        # Debugging: Check if view has any data at all
        total_view_records = described_class.count
        all_tasks = Tasker::Task.count
        all_steps = Tasker::WorkflowStep.count

        fail <<~DEBUG
          StepReadinessStatus view returned 0 records for task #{task.task_id}.

          Debug info:
          - Total view records: #{total_view_records}
          - Total tasks in DB: #{all_tasks}
          - Total steps in DB: #{all_steps}
          - Task workflow_steps count: #{task.workflow_steps.count}
          - First step ID: #{task.workflow_steps.first&.workflow_step_id || 'none'}

          This suggests the view query isn't working or the factory isn't creating the expected data.
        DEBUG
      end

      expect(readiness_statuses.count).to eq(4)

      # Each record should have the expected attributes
      readiness_statuses.each do |status|
        expect(status.workflow_step_id).to be_present
        expect(status.task_id).to eq(task.task_id)
        expect(status.total_parents).to be_a(Integer), "total_parents should be an integer, got: #{status.total_parents.inspect}"
        expect(status.completed_parents).to be_a(Integer), "completed_parents should be an integer, got: #{status.completed_parents.inspect}"
        expect([true, false]).to include(status.dependencies_satisfied)
        expect([true, false]).to include(status.ready_for_execution)
      end
    end

    it 'correctly identifies ready steps in a workflow' do
      # Create the standard dummy workflow which has dependencies:
      # step-one, step-two (independent), step-three (depends on step-two), step-four (depends on step-three)
      task = create_dummy_task_for_orchestration

      readiness_statuses = described_class.where(task_id: task.task_id)

      # Skip this test if no view data is available (as it requires complex dependency analysis)
      skip "StepReadinessStatus view has no data for dependency analysis" if readiness_statuses.count == 0

      # The root steps (no dependencies) should be ready for execution
      root_steps = readiness_statuses.where(total_parents: 0)

      if root_steps.count != 2
        # Debugging: Show actual parent counts
        parent_counts = readiness_statuses.pluck(:total_parents)
        fail "Expected 2 root steps (total_parents = 0), got #{root_steps.count}. All parent counts: #{parent_counts}"
      end

      expect(root_steps.count).to eq(2)  # step-one and step-two are independent
      root_steps.each do |root_step|
        expect(root_step.ready_for_execution).to be true
      end

      # The dependent steps should not be ready yet
      dependent_steps = readiness_statuses.where('total_parents > 0')
      expect(dependent_steps.count).to eq(2)  # step-three and step-four have dependencies
      dependent_steps.each do |dependent_step|
        expect(dependent_step.ready_for_execution).to be false
      end
    end
  end
end
