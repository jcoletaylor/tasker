class CreateTaskerTaskWorkflowSummaries < ActiveRecord::Migration[7.2]
  def change
    create_view :tasker_task_workflow_summaries
  end
end
