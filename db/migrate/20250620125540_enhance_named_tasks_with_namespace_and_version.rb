# frozen_string_literal: true

class EnhanceNamedTasksWithNamespaceAndVersion < ActiveRecord::Migration[7.2]
  def change
    # Add new columns to named_tasks
    add_reference :tasker_named_tasks, :task_namespace, null: false, default: 1,
                                                        foreign_key: { to_table: :tasker_task_namespaces, primary_key: :task_namespace_id },
                                                        index: { name: 'named_tasks_task_namespace_id_index' }

    add_column :tasker_named_tasks, :version, :string, limit: 16, null: false, default: '0.1.0'
    add_column :tasker_named_tasks, :configuration, :jsonb, default: '{}'

    # Add indexes for performance
    add_index :tasker_named_tasks, :version, name: 'named_tasks_version_index'
    add_index :tasker_named_tasks, :configuration, using: :gin, name: 'named_tasks_configuration_gin_index'

    # Remove old unique constraint and add new one
    remove_index :tasker_named_tasks, name: 'named_tasks_name_unique'
    add_index :tasker_named_tasks, %i[task_namespace_id name version],
              unique: true, name: 'named_tasks_namespace_name_version_unique'

    # Data migration: set all existing records to default namespace and version
    reversible do |dir|
      dir.up do
        # Ensure default namespace exists (should be created by previous migration)
        execute <<-SQL.squish
          UPDATE tasker_named_tasks
          SET task_namespace_id = 1, version = '0.1.0'
          WHERE task_namespace_id IS NULL OR version IS NULL;
        SQL
      end
    end
  end
end
