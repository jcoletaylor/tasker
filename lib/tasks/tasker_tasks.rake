# frozen_string_literal: true

namespace :tasker do
  namespace :install do
    # @!method database_objects
    # @description Copies required database views, functions, and init schema from Tasker gem to host application
    # @example Install database objects
    #   rake tasker:install:database_objects
    desc 'Copy Tasker database views, functions, and init schema to your application'
    task database_objects: :environment do
      require 'fileutils'

      puts 'Installing Tasker database objects...'

      # Check and configure SQL schema format
      check_and_configure_sql_schema_format

      # Find the Tasker gem path using multiple methods for reliability
      tasker_gem_path = find_tasker_gem_path

      if tasker_gem_path.blank?
        puts '❌ Could not find Tasker gem path'
        puts '   Please ensure Tasker gem is properly installed'
        exit 1
      end

      puts "📍 Found Tasker gem at: #{tasker_gem_path}"

      # Copy database views
      copy_database_directory(tasker_gem_path, 'views')

      # Copy database functions
      copy_database_directory(tasker_gem_path, 'functions')

      # Copy init schema
      copy_database_directory(tasker_gem_path, 'init')

      puts '✅ Tasker database objects installed successfully!'
      puts ''
      puts 'Next steps:'
      puts '  1. Run migrations: bundle exec rails db:migrate'
      puts '  2. Setup Tasker: bundle exec rails tasker:setup'
    end

    private

    # Find Tasker gem path using multiple detection methods
    #
    # @return [String, nil] Path to Tasker gem or nil if not found
    def find_tasker_gem_path
      # Method 1: Use bundle show (most reliable)
      tasker_gem_path = `bundle show tasker-engine 2>/dev/null`.strip
      return tasker_gem_path unless tasker_gem_path.empty?

      # Method 2: Use Bundler specs
      begin
        require 'bundler'
        spec = Bundler.load.specs.find { |s| s.name == 'tasker-engine' }
        return spec.full_gem_path if spec
      rescue StandardError => e
        puts "   ⚠️  Bundler spec detection failed: #{e.message}"
      end

      # Method 3: Use Tasker::Engine if available
      begin
        require 'tasker'
        return Tasker::Engine.root.to_s if defined?(Tasker::Engine)
      rescue StandardError => e
        puts "   ⚠️  Engine detection failed: #{e.message}"
      end

      # Method 4: Try to find gem in default gem paths
      begin
        gem_paths = Gem.path
        gem_paths.each do |gem_path|
          potential_path = File.join(gem_path, 'gems')
          Dir.glob(File.join(potential_path, 'tasker-engine-*')).each do |tasker_dir|
            return tasker_dir if File.directory?(File.join(tasker_dir, 'db'))
          end
        end
      rescue StandardError => e
        puts "   ⚠️  Gem path detection failed: #{e.message}"
      end

      nil
    end

    # Copy a database directory (views or functions) from gem to application
    #
    # @param gem_path [String] Path to Tasker gem
    # @param directory_name [String] Name of directory to copy ('views' or 'functions')
    def copy_database_directory(gem_path, directory_name)
      source_path = File.join(gem_path, 'db', directory_name)
      target_path = Rails.root.join('db', directory_name)

      if Dir.exist?(source_path)
        # Create target directory if it doesn't exist
        FileUtils.mkdir_p(File.dirname(target_path))

        # Copy the entire directory
        begin
          FileUtils.cp_r(source_path, Rails.root.join('db').to_s)

          # Count files copied
          file_count = Dir.glob(File.join(target_path, '**', '*')).count { |f| File.file?(f) }

          puts "   ✓ Copied #{file_count} #{directory_name} files to db/#{directory_name}/"
        rescue StandardError => e
          puts "   ❌ Failed to copy #{directory_name} directory: #{e.message}"
          puts '      Please check file system permissions and available disk space.'
          exit 1
        end
      else
        puts "   ⚠️  #{directory_name.capitalize} directory not found at #{source_path}"
        puts '      This may indicate an incomplete Tasker installation'
      end
    end

    # Check if SQL schema format is configured and offer to fix it if needed
    def check_and_configure_sql_schema_format
      application_rb_path = Rails.root.join('config/application.rb')

      unless File.exist?(application_rb_path)
        puts "⚠️  Application file not found: #{application_rb_path}"
        puts '   This is unexpected for a Rails application.'
        return
      end

      application_content = File.read(application_rb_path)

      if application_content.include?('config.active_record.schema_format = :sql')
        puts '✅ SQL schema format already configured'
        return
      end

      puts ''
      puts '⚠️  IMPORTANT: SQL Schema Format Configuration Required'
      puts ''
      puts '   Tasker uses database functions and views that are not preserved'
      puts "   in Rails' default schema.rb file. To ensure these database objects"
      puts '   are properly recreated during test database drops/recreates, you'
      puts '   need to configure Rails to use structure.sql instead.'
      puts ''
      puts '   This requires adding the following line to config/application.rb:'
      puts '   config.active_record.schema_format = :sql'
      puts ''
      print '   Would you like me to add this configuration automatically? (y/n): '

      response = $stdin.gets.chomp.downcase

      if %w[y yes].include?(response)
        if update_application_rb_schema_format(application_rb_path, application_content)
          puts '✅ SQL schema format configured successfully!'
          puts '   Your application will now use db/structure.sql instead of db/schema.rb'
        else
          puts '❌ Failed to update application.rb automatically'
          puts '   Please manually add: config.active_record.schema_format = :sql'
          puts '   to your config/application.rb file inside the Application class'
        end
      else
        puts '⚠️  Skipping automatic configuration.'
        puts '   WARNING: Database functions and views may not work correctly'
        puts '   in test environments without this configuration.'
        puts ''
        puts '   To configure manually, add this line to config/application.rb:'
        puts '   config.active_record.schema_format = :sql'
      end
      puts ''
    end

    # Update application.rb to include SQL schema format configuration
    #
    # @param application_rb_path [String] Path to application.rb file
    # @param application_content [String] Current content of application.rb
    # @return [Boolean] Success status
    def update_application_rb_schema_format(application_rb_path, application_content)
      if application_content.include?('class Application < Rails::Application')
        # Add SQL schema format configuration
        new_application_content = application_content.gsub(
          /(class Application < Rails::Application\s*\n)/,
          "\\1    # Configure SQL schema format to preserve database functions and views\n    config.active_record.schema_format = :sql\n\n"
        )

        begin
          File.write(application_rb_path, new_application_content)
          true
        rescue StandardError => e
          puts "   Error writing to application.rb: #{e.message}"
          false
        end
      else
        puts '   Could not find Application class in application.rb'
        false
      end
    end
  end

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
    task_handler_dir = Rails.root.join('app', Tasker::Configuration.configuration.engine.task_handler_directory)
    task_config_dir = Rails.root.join('config', Tasker::Configuration.configuration.engine.task_config_directory)
    task_spec_dir = Rails.root.join('spec', Tasker::Configuration.configuration.engine.task_handler_directory)

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
      Tasker::Telemetry::ExportCoordinator.instance

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
      config = Tasker::Configuration.configuration.telemetry
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
