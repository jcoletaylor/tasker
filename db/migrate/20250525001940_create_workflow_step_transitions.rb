# frozen_string_literal: true

class CreateWorkflowStepTransitions < ActiveRecord::Migration[7.2]
  def change
    create_table :tasker_workflow_step_transitions do |t|
      t.string :to_state, null: false
      t.string :from_state, null: true
      t.jsonb :metadata, default: {}
      t.integer :sort_key, null: false
      t.boolean :most_recent, null: false, default: true
      t.references :workflow_step, null: false,
                                   foreign_key: { to_table: :tasker_workflow_steps, primary_key: :workflow_step_id }

      t.timestamps
    end

    add_index :tasker_workflow_step_transitions, :sort_key
    add_index :tasker_workflow_step_transitions, %i[workflow_step_id sort_key], unique: true
    add_index :tasker_workflow_step_transitions, %i[workflow_step_id most_recent], unique: true,
                                                                                   where: 'most_recent = true'
  end
end
