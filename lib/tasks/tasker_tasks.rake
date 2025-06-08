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
end
