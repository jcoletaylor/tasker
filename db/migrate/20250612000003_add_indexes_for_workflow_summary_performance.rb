# frozen_string_literal: true

class AddIndexesForWorkflowSummaryPerformance < ActiveRecord::Migration[7.2]
  def up
    # The task workflow summary view performs aggregations on active step readiness data
    # We need to ensure efficient GROUP BY task_id operations and filtering

    # Index for efficient task_id grouping in workflow summary aggregations
    # This supports the main GROUP BY task_id operations in the workflow summary view
    add_index :tasker_workflow_steps,
              [:task_id, :workflow_step_id],
              where: "processed = false OR processed IS NULL",
              name: 'idx_workflow_steps_task_grouping_active'

    # Index for efficient dependency resolution in step readiness calculations
    # This supports the dependency checking joins in the active step readiness view
    add_index :tasker_workflow_step_edges,
              [:to_step_id, :from_step_id],
              name: 'idx_workflow_step_edges_dependency_lookup'

    # Composite index for workflow summary scopes on the view itself
    # Since the view will be queried with WHERE clauses on calculated fields,
    # we should consider adding indexes on the view if PostgreSQL supports it
    # For now, we rely on the underlying table indexes

    # Index to support workflow efficiency and processing strategy queries
    # This helps with the common scope patterns in TaskWorkflowSummary model
    add_index :tasker_tasks,
              [:task_id, :complete],
              where: "complete = false OR complete IS NULL",
              name: 'idx_tasks_active_workflow_summary'
  end

  def down
    remove_index :tasker_tasks, name: 'idx_tasks_active_workflow_summary'
    remove_index :tasker_workflow_step_edges, name: 'idx_workflow_step_edges_dependency_lookup'
    remove_index :tasker_workflow_steps, name: 'idx_workflow_steps_task_grouping_active'
  end
end
