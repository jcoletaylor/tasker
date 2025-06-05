class AddIndexesForStepReadinessViews < ActiveRecord::Migration[7.2]
  def change
    # Indexes for workflow step transitions (critical for current state determination)
    add_index :tasker_workflow_step_transitions,
              [:workflow_step_id, :created_at],
              name: 'index_step_transitions_for_current_state'

    # Index for workflow step edges (critical for dependency checks)
    add_index :tasker_workflow_step_edges,
              [:to_step_id],
              name: 'index_step_edges_child_lookup'

    add_index :tasker_workflow_step_edges,
              [:from_step_id],
              name: 'index_step_edges_parent_lookup'

    # Composite index for efficient dependency resolution
    add_index :tasker_workflow_step_edges,
              [:to_step_id, :from_step_id],
              name: 'index_step_edges_dependency_pair'

    # Index for workflow steps by task (critical for task-level queries)
    add_index :tasker_workflow_steps,
              [:task_id],
              name: 'index_workflow_steps_by_task'

    # Composite index for step readiness queries
    add_index :tasker_workflow_steps,
              [:task_id, :workflow_step_id],
              name: 'index_workflow_steps_task_and_id'

    # Index for retry-related fields
    add_index :tasker_workflow_steps,
              [:attempts, :retry_limit],
              name: 'index_workflow_steps_retry_status'

    # Index for failed transitions with timing
    add_index :tasker_workflow_step_transitions,
              [:workflow_step_id, :to_state, :created_at],
              where: "to_state = 'failed'",
              name: 'index_step_transitions_failures_with_timing'

    # Index for completed transitions
    add_index :tasker_workflow_step_transitions,
              [:workflow_step_id, :to_state],
              where: "to_state = 'complete'",
              name: 'index_step_transitions_completed'

    # Index for task transitions (for task-level state determination)
    add_index :tasker_task_transitions,
              [:task_id, :created_at],
              name: 'index_task_transitions_current_state'
  end
end
