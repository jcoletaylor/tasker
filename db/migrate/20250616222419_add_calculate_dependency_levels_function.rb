# frozen_string_literal: true

class AddCalculateDependencyLevelsFunction < ActiveRecord::Migration[7.2]
  def up
    # Load the SQL function from file
    sql_file_path = Tasker::Engine.root.join('db', 'functions', 'calculate_dependency_levels_v01.sql')
    execute File.read(sql_file_path)
  end

  def down
    execute 'DROP FUNCTION IF EXISTS calculate_dependency_levels(BIGINT);'
  end
end
