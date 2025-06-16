# frozen_string_literal: true

class CreateTaskExecutionContextFunction < ActiveRecord::Migration[7.0]
  def up
    function_sql = File.read(Tasker::Engine.root.join('db', 'functions', 'get_task_execution_context_v01.sql'))
    execute(function_sql)
  end

  def down
    execute 'DROP FUNCTION IF EXISTS get_task_execution_context(BIGINT);'
  end
end
