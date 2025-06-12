# frozen_string_literal: true

class OptimizeTaskExecutionContextPerformance < ActiveRecord::Migration[7.2]
  def up
    # Add composite index for the optimized task execution context query
    # This supports the JOIN pattern: tasks -> workflow_steps -> step_readiness_statuses
    add_index :tasker_workflow_steps,
              [:task_id, :workflow_step_id],
              name: 'index_workflow_steps_task_and_step_optimized'
  end

  def down
    # Remove the optimization indexes
    remove_index :tasker_workflow_steps, name: 'index_workflow_steps_task_and_step_optimized'
  end
end
