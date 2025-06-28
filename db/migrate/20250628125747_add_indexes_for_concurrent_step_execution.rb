# frozen_string_literal: true

class AddIndexesForConcurrentStepExecution < ActiveRecord::Migration[7.2]
  def up
    # Phase 1.3: Query Performance Optimization for Concurrent Step Execution
    # Based on analysis of SQL functions and existing WorkflowStepEdge.sibling_sql logic

    # Index for the hot path in get_step_readiness_status function
    # Supports: WHERE ws.task_id = input_task_id AND ws.processed = false
    add_index :tasker_workflow_steps,
              %i[task_id processed workflow_step_id],
              where: 'processed = false',
              name: 'idx_workflow_steps_task_readiness'

    # Index for efficient step transition lookups in all SQL functions
    # Supports: most_recent = true filtering which is used extensively
    add_index :tasker_workflow_step_transitions,
              %i[workflow_step_id most_recent to_state],
              where: 'most_recent = true',
              name: 'idx_step_transitions_current_state'

    # Index for sibling_sql CTE queries and dependency resolution
    # Supports: WHERE to_step_id = step_id in step_parents CTE
    # Also supports: JOIN dep_edges ON dep_edges.to_step_id = ws.workflow_step_id in SQL functions
    add_index :tasker_workflow_step_edges,
              %i[to_step_id from_step_id],
              name: 'idx_step_edges_to_from'

    # Index for sibling_sql potential_siblings CTE
    # Supports: WHERE from_step_id IN (parent_ids) in potential_siblings CTE
    add_index :tasker_workflow_step_edges,
              %i[from_step_id to_step_id],
              name: 'idx_step_edges_from_to'
  end

  def down
    remove_index :tasker_workflow_step_edges, name: 'idx_step_edges_from_to'
    remove_index :tasker_workflow_step_edges, name: 'idx_step_edges_to_from'
    remove_index :tasker_workflow_step_transitions, name: 'idx_step_transitions_current_state'
    remove_index :tasker_workflow_steps, name: 'idx_workflow_steps_task_readiness'
  end
end
