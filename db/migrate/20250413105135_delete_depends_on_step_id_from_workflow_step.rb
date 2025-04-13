# frozen_string_literal: true

class DeleteDependsOnStepIdFromWorkflowStep < ActiveRecord::Migration[7.2]
  def change
    remove_column :tasker_workflow_steps, :depends_on_step_id, :bigint
  end
end
