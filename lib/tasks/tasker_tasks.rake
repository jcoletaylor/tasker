# frozen_string_literal: true

namespace :tasker do
  desc 'Initialize Tasker by creating the configuration file in config/initializers'
  task init: :environment do
    require 'fileutils'

    # Source template file
    template_path = File.expand_path('../generators/task_handler/templates/initialize.rb.erb', __dir__)

    # Target path in the Rails app
    target_path = Rails.root.join('config/initializers/tasker.rb')

    if File.exist?(target_path)
      puts "Configuration file already exists at #{target_path}."
      puts 'To overwrite, use tasker:init:force'
    else
      FileUtils.cp(template_path, target_path)
      puts "Tasker configuration initialized at #{target_path}"
    end
  end

  namespace :init do
    desc 'Force initialize Tasker by overwriting existing configuration file'
    task force: :environment do
      require 'fileutils'

      # Source template file
      template_path = File.expand_path('../generators/task_handler/templates/initialize.rb.erb', __dir__)

      # Target path in the Rails app
      target_path = Rails.root.join('config/initializers/tasker.rb')

      FileUtils.cp(template_path, target_path)
      puts "Tasker configuration initialized at #{target_path}"
    end
  end

  desc 'Setup Tasker with configuration and directory structure'
  task setup: :environment do
    require 'fileutils'

    # Run the init task
    Rake::Task['tasker:init'].invoke

    # Get configuration
    require Rails.root.join('config/initializers/tasker.rb')

    # Create necessary directories based on configuration
    task_handler_dir = Rails.root.join('app', Tasker.configuration.task_handler_directory)
    task_config_dir = Rails.root.join('config', Tasker.configuration.task_config_directory)
    task_spec_dir = Rails.root.join('spec', Tasker.configuration.task_handler_directory)

    dirs = [task_handler_dir, task_config_dir, task_spec_dir]

    dirs.each do |dir|
      unless File.directory?(dir)
        FileUtils.mkdir_p(dir)
        puts "Created directory: #{dir}"
      end
    end

    puts 'Tasker setup complete!'
    puts 'You can now generate task handlers with: rails generate task_handler NAME'
  end
end
