# frozen_string_literal: true

class CreateTaskerWorkflowStepEdges < ActiveRecord::Migration[7.2]
  def change
    create_table :tasker_workflow_step_edges do |t|
      t.references :from_step, null: false,
                               foreign_key: {
                                 to_table: :tasker_workflow_steps,
                                 primary_key: :workflow_step_id
                               }
      t.references :to_step, null: false,
                             foreign_key: { to_table: :tasker_workflow_steps, primary_key: :workflow_step_id }
      t.string :name, null: false

      t.timestamps
    end
  end
end
