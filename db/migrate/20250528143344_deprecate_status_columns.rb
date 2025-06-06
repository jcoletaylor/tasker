# frozen_string_literal: true

class DeprecateStatusColumns < ActiveRecord::Migration[7.2]
  def change
    # Remove status columns entirely - we're using state machines now
    remove_column :tasker_tasks, :status, :string
    remove_column :tasker_workflow_steps, :status, :string
  end
end
