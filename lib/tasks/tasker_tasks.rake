# frozen_string_literal: true

namespace :tasker do
  # @!method setup
  # @description Initializes Tasker by creating the configuration file and necessary directory structure
  # @example Run setup task
  #   rake tasker:setup
  desc 'Setup Tasker with configuration and directory structure'
  task setup: :environment do
    require 'fileutils'

    # Source template file
    template_path = File.expand_path('../generators/tasker/templates/initialize.rb.erb', __dir__)
    # Target path in the Rails app
    target_path = Rails.root.join('config/initializers/tasker.rb')

    # Create config file if it doesn't exist
    if File.exist?(target_path)
      puts "Configuration file already exists at #{target_path}."
      puts 'To overwrite, use tasker:setup:force'
    else
      FileUtils.cp(template_path, target_path)
      puts "Tasker configuration initialized at #{target_path}"

      # Only load config if we just created it (otherwise could error if invalid)
      require target_path
    end

    # Create necessary directories based on configuration
    task_handler_dir = Rails.root.join('app', Tasker.configuration.engine.task_handler_directory)
    task_config_dir = Rails.root.join('config', Tasker.configuration.engine.task_config_directory)
    task_spec_dir = Rails.root.join('spec', Tasker.configuration.engine.task_handler_directory)

    [task_handler_dir, task_config_dir, task_spec_dir].each do |dir|
      unless File.directory?(dir)
        FileUtils.mkdir_p(dir)
        puts "Created directory: #{dir}"
      end
    end

    puts 'Tasker setup complete!'
    puts 'You can now generate task handlers with: rails generate task_handler NAME'
  end

  namespace :setup do
    # @!method force
    # @description Forcibly initializes Tasker by overwriting the existing configuration file
    # @example Run force setup task
    #   rake tasker:setup:force
    desc 'Force setup Tasker by overwriting existing configuration file'
    task force: :environment do
      require 'fileutils'

      # Source template file
      template_path = File.expand_path('../generators/tasker/templates/initialize.rb.erb', __dir__)
      # Target path in the Rails app
      target_path = Rails.root.join('config/initializers/tasker.rb')

      # Always copy the file
      FileUtils.cp(template_path, target_path)
      puts "Tasker configuration initialized at #{target_path}"

      # Now run the regular setup task to create directories
      Rake::Task['tasker:setup'].reenable
      Rake::Task['tasker:setup'].invoke
    end
  end

  desc 'Export metrics to configured storage backends'
  task :export_metrics, [:format] => :environment do |_task, args|
    format = (args[:format] || ENV['METRICS_FORMAT'] || 'prometheus').to_sym

    puts "Starting metrics export (format: #{format})"

    begin
      coordinator = Tasker::Telemetry::ExportCoordinator.new
      result = coordinator.schedule_export(format: format)

      if result[:success]
        puts '✅ Metrics export scheduled successfully'
        puts "   Job ID: #{result[:job_id]}"
        puts "   Export time: #{result[:export_time]}"
        puts "   Format: #{result[:format]}"
      else
        puts "❌ Metrics export scheduling failed: #{result[:error]}"
        exit 1
      end
    rescue StandardError => e
      puts "❌ Metrics export error: #{e.message}"
      puts e.backtrace.first(5).join("\n") if ENV['VERBOSE']
      exit 1
    end
  end

  desc 'Export metrics immediately (synchronous)'
  task :export_metrics_now, [:format] => :environment do |_task, args|
    format = (args[:format] || ENV['METRICS_FORMAT'] || 'prometheus').to_sym

    puts "Starting immediate metrics export (format: #{format})"

    begin
      coordinator = Tasker::Telemetry::ExportCoordinator.new
      result = coordinator.execute_coordinated_export(format: format)

      if result[:success]
        puts '✅ Metrics exported successfully'
        puts "   Format: #{result[:format]}"
        puts "   Metrics count: #{result[:metrics_count] || 'unknown'}"
        puts "   Duration: #{result[:duration]&.round(3)}s"
      else
        puts "❌ Metrics export failed: #{result[:error]}"
        exit 1
      end
    rescue StandardError => e
      puts "❌ Metrics export error: #{e.message}"
      puts e.backtrace.first(5).join("\n") if ENV['VERBOSE']
      exit 1
    end
  end

  desc 'Sync metrics to cache storage'
  task sync_metrics: :environment do
    puts 'Starting metrics cache synchronization'

    begin
      backend = Tasker::Telemetry::MetricsBackend.instance
      result = backend.sync_to_cache!

      if result[:success]
        puts '✅ Metrics synchronized successfully'
        puts "   Strategy: #{result[:strategy]}"
        puts "   Synced metrics: #{result[:synced_metrics] || result[:total_synced]}"
        puts "   Duration: #{result[:duration]&.round(3)}s"
      else
        puts "❌ Metrics sync failed: #{result[:error]}"
        exit 1
      end
    rescue StandardError => e
      puts "❌ Metrics sync error: #{e.message}"
      puts e.backtrace.first(5).join("\n") if ENV['VERBOSE']
      exit 1
    end
  end

  desc 'Show metrics export status and configuration'
  task metrics_status: :environment do
    puts 'Tasker Metrics Export Status'
    puts '=' * 40

    begin
      backend = Tasker::Telemetry::MetricsBackend.instance
      Tasker::Telemetry::ExportCoordinator.new

      # Backend status
      puts 'Backend Status:'
      puts "  Instance ID: #{backend.instance_id}"
      puts "  Sync Strategy: #{backend.sync_strategy}"
      puts "  Cache Store: #{backend.cache_capabilities[:store_class]}"
      puts "  Metrics Count: #{backend.all_metrics.size}"

      # Cache capabilities
      puts "\nCache Capabilities:"
      backend.cache_capabilities.each do |key, value|
        puts "  #{key}: #{value}"
      end

      # Configuration
      config = Tasker.configuration.telemetry
      puts "\nTelemetry Configuration:"
      puts "  Enabled: #{config.enabled}"
      puts "  Metrics Enabled: #{config.metrics_enabled}"
      puts "  Metrics Format: #{config.metrics_format}"
      puts "  Metrics Endpoint: #{config.metrics_endpoint}"
      puts "  Auth Required: #{config.metrics_auth_required}"

      # Prometheus config
      if config.prometheus
        puts "\nPrometheus Configuration:"
        puts "  Endpoint: #{config.prometheus[:endpoint] || 'not configured'}"
        puts "  Retention Window: #{config.prometheus[:retention_window]}"
        puts "  Safety Margin: #{config.prometheus[:safety_margin]}"
        puts "  Export Timeout: #{config.prometheus[:export_timeout]}"
      end
    rescue StandardError => e
      puts "❌ Status check error: #{e.message}"
      exit 1
    end
  end
end
