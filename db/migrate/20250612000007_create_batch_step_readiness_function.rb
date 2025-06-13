# frozen_string_literal: true

class CreateBatchStepReadinessFunction < ActiveRecord::Migration[7.0]
  def up
    function_sql = File.read(Tasker::Engine.root.join('db', 'functions', 'get_step_readiness_status_batch_v01.sql'))
    execute(function_sql)
  end

  def down
    execute 'DROP FUNCTION IF EXISTS get_step_readiness_status_batch(BIGINT[]);'
  end
end
