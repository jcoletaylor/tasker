# frozen_string_literal: true

class CreateTaskerTaskNamespaces < ActiveRecord::Migration[7.2]
  def change
    create_table :tasker_task_namespaces, primary_key: :task_namespace_id, id: :serial do |t|
      t.string :name, limit: 64, null: false
      t.string :description, limit: 255

      t.timestamps null: false
    end

    add_index :tasker_task_namespaces, :name, unique: true, name: 'task_namespaces_name_unique'
    add_index :tasker_task_namespaces, :name, name: 'task_namespaces_name_index'

    # Insert default namespace
    reversible do |dir|
      dir.up do
        execute <<-SQL.squish
          INSERT INTO tasker_task_namespaces (name, description, created_at, updated_at)
          VALUES ('default', 'Default task namespace', NOW(), NOW());
        SQL
      end
    end
  end
end
