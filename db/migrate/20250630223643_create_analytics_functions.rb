# frozen_string_literal: true

class CreateAnalyticsFunctions < ActiveRecord::Migration[7.2]
  def up
    # Analytics metrics function for comprehensive performance data
    analytics_metrics_sql = File.read(Tasker::Engine.root.join('db', 'functions', 'get_analytics_metrics_v01.sql'))
    execute(analytics_metrics_sql)

    # Slowest tasks analysis function
    slowest_tasks_sql = File.read(Tasker::Engine.root.join('db', 'functions', 'get_slowest_tasks_v01.sql'))
    execute(slowest_tasks_sql)

    # Slowest steps analysis function
    slowest_steps_sql = File.read(Tasker::Engine.root.join('db', 'functions', 'get_slowest_steps_v01.sql'))
    execute(slowest_steps_sql)
  end

  def down
    execute('DROP FUNCTION IF EXISTS get_analytics_metrics_v01(TIMESTAMPTZ);')
    execute('DROP FUNCTION IF EXISTS get_slowest_tasks_v01(TIMESTAMPTZ, INTEGER, TEXT, TEXT, TEXT);')
    execute('DROP FUNCTION IF EXISTS get_slowest_steps_v01(TIMESTAMPTZ, INTEGER, TEXT, TEXT, TEXT);')
  end
end
