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
    @module_namespace = options[:module_namespace]
    @class_name = name.camelize
    @task_name = name.underscore
    @concurrent = options[:concurrent]
    @dependent_system = options[:dependent_system]

    # Create the YAML config file
    template 'task_config.yaml.erb', "config/tasks/#{@task_name}.yaml"

    # Create the task handler class
    template 'task_handler.rb.erb', "app/tasks/#{@task_name}.rb"

    # Create the step handler module
    template 'step_handler.rb.erb', "app/tasks/#{@task_name}/step_handler.rb"

    # Create the task handler spec
    template 'task_handler_spec.rb.erb', "spec/tasks/#{@task_name}_spec.rb"
  end
end
