# frozen_string_literal: true

class OptimizeDatabaseViewsForScale < ActiveRecord::Migration[7.2]
  def up
    # Add critical missing indexes for performance at scale
    add_performance_indexes
  end

  def down
    # Remove the performance indexes
    remove_performance_indexes
  end

  private

  def add_performance_indexes
    # Critical index for state machine current state queries using most_recent flag
    add_index :tasker_task_transitions,
              %i[task_id most_recent],
              where: 'most_recent = true',
              name: 'index_task_transitions_current_state_optimized'

    add_index :tasker_workflow_step_transitions,
              %i[workflow_step_id most_recent],
              where: 'most_recent = true',
              name: 'index_step_transitions_current_state_optimized'

    # Composite index for step processing flags (critical for readiness)
    add_index :tasker_workflow_steps,
              %i[task_id processed in_process],
              name: 'index_workflow_steps_processing_status'

    # Index for retry logic queries
    add_index :tasker_workflow_steps,
              %i[attempts retry_limit retryable],
              name: 'index_workflow_steps_retry_logic'

    # Index for backoff calculations
    add_index :tasker_workflow_steps,
              %i[last_attempted_at backoff_request_seconds],
              where: 'backoff_request_seconds IS NOT NULL',
              name: 'index_workflow_steps_backoff_timing'

    # Optimized index for error state transitions with timing
    add_index :tasker_workflow_step_transitions,
              %i[workflow_step_id most_recent created_at],
              where: "to_state = 'error' AND most_recent = true",
              name: 'index_step_transitions_current_errors'

    # Index for completed parent dependency checks
    add_index :tasker_workflow_step_transitions,
              %i[workflow_step_id most_recent],
              where: "to_state IN ('complete', 'resolved_manually') AND most_recent = true",
              name: 'index_step_transitions_completed_parents'

    # Covering index for task execution context aggregation
    add_index :tasker_workflow_steps,
              [:task_id],
              include: %i[workflow_step_id processed in_process attempts retry_limit],
              name: 'index_workflow_steps_task_covering'

    # Index for dependency edge lookups (optimizes the new direct join approach)
    add_index :tasker_workflow_step_edges,
              %i[to_step_id from_step_id],
              name: 'index_workflow_step_edges_dependency_lookup'
  end

  def remove_performance_indexes
    remove_index :tasker_task_transitions, name: 'index_task_transitions_current_state_optimized'
    remove_index :tasker_workflow_step_transitions, name: 'index_step_transitions_current_state_optimized'
    remove_index :tasker_workflow_steps, name: 'index_workflow_steps_processing_status'
    remove_index :tasker_workflow_steps, name: 'index_workflow_steps_retry_logic'
    remove_index :tasker_workflow_steps, name: 'index_workflow_steps_backoff_timing'
    remove_index :tasker_workflow_step_transitions, name: 'index_step_transitions_current_errors'
    remove_index :tasker_workflow_step_transitions, name: 'index_step_transitions_completed_parents'
    remove_index :tasker_workflow_steps, name: 'index_workflow_steps_task_covering'
    remove_index :tasker_workflow_step_edges, name: 'index_workflow_step_edges_dependency_lookup'
  end
end
