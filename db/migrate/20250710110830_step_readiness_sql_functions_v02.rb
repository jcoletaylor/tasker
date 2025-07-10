class StepReadinessSqlFunctionsV02 < ActiveRecord::Migration[7.2]
  def up
    sql_file = File.read(Rails.root.join('db', 'functions', 'get_step_readiness_status_single_and_batch_v02.sql'))
    execute(sql_file)
  end

  def down
    original_sql_files = [
      'get_step_readiness_status_v01.sql',
      'get_step_readiness_status_batch_v01.sql'
    ]

    original_sql_files.each do |file|
      sql_file = File.read(Rails.root.join('db', 'functions', file))
      execute(sql_file)
    end
  end
end
