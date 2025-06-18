# frozen_string_literal: true

class CreateSystemHealthCountsFunction < ActiveRecord::Migration[7.2]
  def up
    function_sql = File.read(Tasker::Engine.root.join('db', 'functions', 'get_system_health_counts_v01.sql'))
    execute(function_sql)
  end

  def down
    execute('DROP FUNCTION IF EXISTS get_system_health_counts_v01();')
  end
end
