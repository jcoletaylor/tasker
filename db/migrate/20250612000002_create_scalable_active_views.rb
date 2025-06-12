# frozen_string_literal: true

class CreateScalableActiveViews < ActiveRecord::Migration[7.2]
  def up
    # Create indexes for active operations performance
    add_active_operations_indexes

    # Create the active step readiness view (Scenic convention)
    create_view :tasker_active_step_readiness_statuses

    # Create the active task execution context view (Scenic convention)
    create_view :tasker_active_task_execution_contexts

    # tasker workflow summary relies on the above views for performance
    create_view :tasker_task_workflow_summaries
  end

  def down
    # Drop the views (Scenic convention)
    drop_view :tasker_task_workflow_summaries
    drop_view :tasker_active_task_execution_contexts
    drop_view :tasker_active_step_readiness_statuses

    # Remove the indexes
    remove_active_operations_indexes
  end

  private

  def add_active_operations_indexes
    # Index for active tasks (incomplete tasks only)
    add_index :tasker_tasks,
              [:task_id],
              where: 'complete = false OR complete IS NULL',
              name: 'idx_tasks_active_operations'

    # Index for active workflow steps (from incomplete tasks)
    add_index :tasker_workflow_steps,
              %i[workflow_step_id task_id],
              where: 'processed = false OR processed IS NULL',
              name: 'idx_steps_active_operations'

    # Composite index for task completion status and creation time
    add_index :tasker_tasks,
              %i[complete created_at task_id],
              name: 'idx_tasks_completion_status_created'

    # Index for task transitions with most_recent flag
    add_index :tasker_task_transitions,
              %i[task_id most_recent],
              where: 'most_recent = true',
              name: 'idx_task_transitions_most_recent'

    # Index for workflow step transitions with most_recent flag
    add_index :tasker_workflow_step_transitions,
              %i[workflow_step_id most_recent],
              where: 'most_recent = true',
              name: 'idx_step_transitions_most_recent'
  end

  def remove_active_operations_indexes
    remove_index :tasker_workflow_step_transitions, name: 'idx_step_transitions_most_recent'
    remove_index :tasker_task_transitions, name: 'idx_task_transitions_most_recent'
    remove_index :tasker_tasks, name: 'idx_tasks_completion_status_created'
    remove_index :tasker_workflow_steps, name: 'idx_steps_active_operations'
    remove_index :tasker_tasks, name: 'idx_tasks_active_operations'
  end
end
