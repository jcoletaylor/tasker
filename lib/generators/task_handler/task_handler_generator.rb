# frozen_string_literal: true

class TaskHandlerGenerator < Rails::Generators::NamedBase
  source_root File.expand_path('templates', __dir__)

  class_option :module_namespace, type: :string, default: 'OurTask',
                                  desc: 'The module namespace for the task handler'
  class_option :concurrent, type: :boolean, default: true,
                            desc: 'Whether the task can be run concurrently'
  class_option :dependent_system, type: :string, default: 'default_system',
                                  desc: 'The default dependent system for the task'

  def create_task_handler_files
    # Set variables first
    @module_namespace = options[:module_namespace]
    @class_name = name.camelize
    @task_name = name.underscore
    @concurrent = options[:concurrent]
    @dependent_system = options[:dependent_system]

    # Load configuration
    ensure_configuration_loaded

    # Get directory paths from configuration
    @task_handler_directory = Tasker.configuration.task_handler_directory
    @task_config_directory = Tasker.configuration.task_config_directory

    # Ensure directories exist
    ensure_directories_exist

    # Create the YAML config file
    template 'task_config.yaml.erb', "config/#{@task_config_directory}/#{@task_name}.yaml"

    # Create the task handler class
    template 'task_handler.rb.erb', "app/#{@task_handler_directory}/#{@task_name}.rb"

    # Create the step handler module
    template 'step_handler.rb.erb', "app/#{@task_handler_directory}/#{@task_name}_step_handler.rb"

    # Create the task handler spec
    template 'task_handler_spec.rb.erb', "spec/#{@task_handler_directory}/#{@task_name}_spec.rb"
  end

  private

  def ensure_configuration_loaded
    # Check if Tasker is already loaded
    return if defined?(Tasker) && Tasker.respond_to?(:configuration)

    initializer_path = Rails.root.join('config/initializers/tasker.rb')

    # Copy initializer if it doesn't exist
    unless File.exist?(initializer_path)
      template_path = File.expand_path('templates/initialize.rb.erb', __dir__)
      FileUtils.cp(template_path, initializer_path)
      Rails.logger.debug { "Created Tasker configuration at #{initializer_path}" }
    end

    # Load the initializer
    require initializer_path
  end

  def ensure_directories_exist
    # Create necessary directories if they don't exist
    task_handler_dir = Rails.root.join('app', @task_handler_directory)
    task_config_dir = Rails.root.join('config', @task_config_directory)
    task_spec_dir = Rails.root.join('spec', @task_handler_directory)

    [task_handler_dir, File.join(task_handler_dir, @task_name), task_config_dir, task_spec_dir].each do |dir|
      FileUtils.mkdir_p(dir) unless File.directory?(dir)
    end
  end
end
