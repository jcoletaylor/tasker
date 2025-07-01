# typed: false
# frozen_string_literal: true

class InitialTaskerSchema < ActiveRecord::Migration[7.2]
  def up
    # Load the complete schema from our init file
    # This ensures we get the exact same database structure that has been tested
    # Handle both engine context and standalone context
    if defined?(Tasker::Engine)
      # When running in engine context, look in the engine root
      engine_root = Tasker::Engine.root
      schema_path = engine_root.join('db', 'init', 'schema.sql')
    else
      # When running standalone, use Rails.root
      schema_path = Rails.root.join('db/init/schema.sql')
    end

    unless File.exist?(schema_path)
      raise "Schema file not found at #{schema_path}. Please ensure db/init/schema.sql exists."
    end

    # Read and execute the schema file
    schema_sql = File.read(schema_path)

    # Filter out Rails internal tables that conflict with Rails' automatic creation
    # These tables are created automatically by Rails during db:create
    filtered_sql = filter_rails_internal_tables(schema_sql)

    # Execute the filtered schema
    execute(filtered_sql)

    # Ensure the migration version is recorded
    # (This happens automatically but being explicit)
  end

  private

  # Filter out Rails internal tables from the schema SQL
  # These tables are automatically created by Rails and will conflict if we try to create them
  def filter_rails_internal_tables(sql)
    lines = sql.lines
    filtered_lines = []
    skip_table = false
    current_table = nil

    lines.each do |line|
      # Detect table creation for Rails internal tables
      if line =~ /CREATE TABLE (?:public\.)?(ar_internal_metadata|schema_migrations)/
        current_table = ::Regexp.last_match(1)
        skip_table = true
        next
      end

      # Detect end of table creation (semicolon on its own line or other CREATE/ALTER statement)
      if skip_table && (line.strip == ';' || line.match(/^(CREATE|ALTER|INSERT|COPY)/))
        if line.strip == ';'
          # Skip the semicolon that ends the table we're filtering
          skip_table = false
          current_table = nil
          next
        elsif /^(CREATE|ALTER|INSERT|COPY)/.match?(line)
          # New statement starts, stop skipping
          skip_table = false
          current_table = nil
          # Don't skip this line, it's a new statement
        end
      end

      # Skip INSERT statements for Rails internal tables
      if line =~ /INSERT INTO (?:public\.)?(ar_internal_metadata|schema_migrations)/
        skip_table = true
        current_table = ::Regexp.last_match(1)
        next
      end

      # Skip COPY statements for Rails internal tables
      if line =~ /COPY (?:public\.)?(ar_internal_metadata|schema_migrations)/
        skip_table = true
        current_table = ::Regexp.last_match(1)
        next
      end

      # Add line if we're not skipping
      filtered_lines << line unless skip_table
    end

    filtered_lines.join
  end

  def down
    # Drop all Tasker tables in reverse dependency order
    execute 'DROP TABLE IF EXISTS tasker_workflow_step_transitions CASCADE;'
    execute 'DROP TABLE IF EXISTS tasker_task_transitions CASCADE;'
    execute 'DROP TABLE IF EXISTS tasker_task_annotations CASCADE;'
    execute 'DROP TABLE IF EXISTS tasker_workflow_step_edges CASCADE;'
    execute 'DROP TABLE IF EXISTS tasker_workflow_steps CASCADE;'
    execute 'DROP TABLE IF EXISTS tasker_tasks CASCADE;'
    execute 'DROP TABLE IF EXISTS tasker_named_tasks_named_steps CASCADE;'
    execute 'DROP TABLE IF EXISTS tasker_named_steps CASCADE;'
    execute 'DROP TABLE IF EXISTS tasker_named_tasks CASCADE;'
    execute 'DROP TABLE IF EXISTS tasker_dependent_system_object_maps CASCADE;'
    execute 'DROP TABLE IF EXISTS tasker_dependent_systems CASCADE;'
    execute 'DROP TABLE IF EXISTS tasker_task_namespaces CASCADE;'
    execute 'DROP TABLE IF EXISTS tasker_annotation_types CASCADE;'

    # Drop views
    execute 'DROP VIEW IF EXISTS tasker_step_dag_relationships CASCADE;'

    # Drop functions
    execute 'DROP FUNCTION IF EXISTS public.get_step_readiness_status(bigint, bigint[]) CASCADE;'
    execute 'DROP FUNCTION IF EXISTS public.get_step_readiness_status_batch(bigint[]) CASCADE;'
    execute 'DROP FUNCTION IF EXISTS public.calculate_dependency_levels(bigint) CASCADE;'
    execute 'DROP FUNCTION IF EXISTS public.get_system_health_counts_v01() CASCADE;'
    execute 'DROP FUNCTION IF EXISTS public.get_analytics_metrics_v01(timestamp with time zone) CASCADE;'
  end
end
