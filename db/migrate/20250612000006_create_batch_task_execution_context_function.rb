class CreateBatchTaskExecutionContextFunction < ActiveRecord::Migration[7.0]
  def up
    # Read and execute the SQL function from file
    # Use the gem's root directory, not Rails.root (which points to dummy app)
    gem_root = File.expand_path('../..', __dir__)
    function_sql = File.read(File.join(gem_root, 'db', 'functions', 'get_task_execution_contexts_batch_v01.sql'))
    execute(function_sql)
  end

  def down
    execute "DROP FUNCTION IF EXISTS get_task_execution_contexts_batch(INTEGER[]);"
  end
end
