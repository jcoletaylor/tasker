# frozen_string_literal: true

class StepReadinessSqlFunctionsV02 < ActiveRecord::Migration[7.2]
  def up
    if defined?(Tasker::Engine)
      # When running in engine context, look in the engine root
      engine_root = Tasker::Engine.root
      sql_file = engine_root.join('db', 'functions', 'get_step_readiness_status_single_and_batch_v02.sql')
    else
      # When running standalone, use Rails.root
      sql_file = Rails.root.join('db/functions/get_step_readiness_status_single_and_batch_v02.sql')
    end

    unless File.exist?(sql_file)
      raise "SQL file not found at #{sql_file}. Please ensure db/functions/get_step_readiness_status_single_and_batch_v02.sql exists."
    end

    execute(File.read(sql_file))
  end

  def down
    path_root = if defined?(Tasker::Engine)
                  # When running in engine context, look in the engine root
                  Tasker::Engine.root
                else
                  # When running standalone, use Rails.root
                  Rails.root
                end
    original_sql_files = [
      'get_step_readiness_status_v01.sql',
      'get_step_readiness_status_batch_v01.sql'
    ]

    original_sql_files.each do |file|
      sql_file = File.read(path_root.join('db', 'functions', file))
      execute(sql_file)
    end
  end
end
