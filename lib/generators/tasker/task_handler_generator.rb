# frozen_string_literal: true

require 'rails/generators'

module Tasker
  module Generators
    class TaskHandlerGenerator < Rails::Generators::NamedBase
      source_root File.expand_path('templates', __dir__)

      desc 'Generate a new Tasker task handler with YAML configuration and tests'

      class_option :module_namespace, type: :string, default: nil,
                                      desc: 'The module namespace for the task handler (defaults to Tasker.configuration.engine.default_module_namespace)'
      class_option :concurrent, type: :boolean, default: true,
                                desc: 'Whether the task can be run concurrently'
      class_option :dependent_system, type: :string, default: 'default_system',
                                      desc: 'The default dependent system for the task'
      class_option :steps, type: :array, default: [],
                           desc: 'Step names to include in the task (e.g., --steps=validate,process,complete)'

      def create_task_handler_files
        # Set variables first
        @module_namespace = options[:module_namespace] || Tasker.configuration.engine.default_module_namespace
        @module_path = @module_namespace&.underscore
        @task_handler_class = name.camelize
        @task_name = name.underscore
        @concurrent = options[:concurrent]
        @dependent_system = options[:dependent_system]
        @steps = options[:steps]

        # Load configuration
        ensure_configuration_loaded

        # Get directory paths from configuration
        @task_handler_directory = Tasker.configuration.engine.task_handler_directory
        @task_config_directory = Tasker.configuration.engine.task_config_directory

        # Ensure directories exist
        ensure_directories_exist(
          [
            task_handler_directory_with_module_path,
            spec_directory_with_module_path,
            task_config_directory_with_module_path
          ]
        )

        # Create the YAML config file
        template 'task_config.yaml.erb', "#{task_config_directory_with_module_path}/#{@task_name}.yaml"

        # Create the task handler class
        template 'task_handler.rb.erb', "#{task_handler_directory_with_module_path}/#{@task_name}.rb"

        # Create the task handler spec
        template 'task_handler_spec.rb.erb', "#{spec_directory_with_module_path}/#{@task_name}_spec.rb"

        display_success_message
      end

      private

      def usable_module_path
        @module_path ? "#{@module_path}/" : ''
      end

      def task_handler_directory_with_module_path
        Rails.root.join("app/#{@task_handler_directory}/#{usable_module_path}")
      end

      def task_config_directory_with_module_path
        Rails.root.join("config/#{@task_config_directory}/#{usable_module_path}")
      end

      def spec_directory_with_module_path
        Rails.root.join("spec/#{@task_handler_directory}/#{usable_module_path}")
      end

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

      def ensure_directories_exist(dirs)
        dirs.each do |dir|
          unless File.directory?(dir)
            FileUtils.mkdir_p(dir)
            Rails.logger.debug { "Created directory: #{dir}" }
          end
        end
      end

      def display_success_message
        say "\nTask handler created successfully!"
        say ''
        say 'Files created:'
        say "  - #{task_handler_directory_with_module_path}/#{@task_name}.rb"
        say "  - #{task_config_directory_with_module_path}/#{@task_name}.yaml"
        say "  - #{spec_directory_with_module_path}/#{@task_name}_spec.rb"
        say ''
        say 'Next steps:'
        say '  1. Define your step handlers in the YAML configuration'
        say '  2. Implement step handlers as needed'
        say "  3. Run your tests: bundle exec rspec spec/#{@task_handler_directory}/#{usable_module_path}#{@task_name}_spec.rb"
        say ''
        say 'Usage example:'
        say '  task_request = Tasker::Types::TaskRequest.new('
        say "    name: '#{@task_name}',"
        say '    context: { /* your task context */ }'
        say '  )'
        say ''
        say "  handler = Tasker::HandlerFactory.instance.get('#{@task_name}')"
        say '  task = handler.initialize_task!(task_request)'
      end
    end
  end
end
