# frozen_string_literal: true

class CreateTaskTransitions < ActiveRecord::Migration[7.2]
  def change
    create_table :tasker_task_transitions do |t|
      t.string :to_state, null: false
      t.string :from_state, null: true
      t.jsonb :metadata, default: {}
      t.integer :sort_key, null: false
      t.boolean :most_recent, null: false, default: true
      t.references :task, null: false, foreign_key: { to_table: :tasker_tasks, primary_key: :task_id }

      t.timestamps
    end

    add_index :tasker_task_transitions, :sort_key
    add_index :tasker_task_transitions, %i[task_id sort_key], unique: true
    add_index :tasker_task_transitions, %i[task_id most_recent], unique: true, where: 'most_recent = true'
  end
end
