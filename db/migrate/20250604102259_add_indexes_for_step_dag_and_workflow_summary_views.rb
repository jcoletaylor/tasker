class AddIndexesForStepDagAndWorkflowSummaryViews < ActiveRecord::Migration[7.2]
  def change
    # Indexes to support tasker_step_dag_relationships view performance

    # Composite index for task-based DAG queries (root/leaf step discovery)
    add_index :tasker_workflow_steps,
              [:task_id, :workflow_step_id],
              name: 'index_workflow_steps_task_and_step_id'

    # Indexes for workflow step edges (critical for DAG relationship calculation)
    add_index :tasker_workflow_step_edges,
              [:from_step_id, :to_step_id],
              name: 'index_step_edges_from_to_composite'

    add_index :tasker_workflow_step_edges,
              [:to_step_id, :from_step_id],
              name: 'index_step_edges_to_from_composite'

    # Index for efficient parent/child aggregation in DAG view
    add_index :tasker_workflow_step_edges,
              [:from_step_id],
              name: 'index_step_edges_from_step_for_children'

    add_index :tasker_workflow_step_edges,
              [:to_step_id],
              name: 'index_step_edges_to_step_for_parents'
  end
end
