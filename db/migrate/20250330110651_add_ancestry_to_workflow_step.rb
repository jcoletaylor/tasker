# frozen_string_literal: true

class AddAncestryToWorkflowStep < ActiveRecord::Migration[7.2]
  def change
    change_table(:tasker_workflow_steps) do |t|
      t.string 'ancestry', collation: 'C', null: false
      t.index 'ancestry'
      t.integer 'ancestry_depth', null: false, default: 0
      t.integer 'children_count', null: false, default: 0
    end
  end
end
