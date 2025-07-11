# frozen_string_literal: true

require 'yaml'
require 'json-schema'

module Tasker
  # Builds task handler classes from configuration
  #
  # TaskBuilder provides a way to dynamically create task handler classes
  # from configuration defined in YAML or passed programmatically.
  # It handles validation, step definition, and handler registration.
  class TaskBuilder
    # @return [Hash] The configuration used to build the task handler
    attr_reader :config

    # @return [Class] The generated task handler class
    attr_reader :handler_class

    # Create a new TaskBuilder with the given configuration
    #
    # @param config [Hash] Configuration hash for building the task handler
    # @return [TaskBuilder] A new task builder instance
    def initialize(config: {})
      @config = deep_merge_configs(config)
      validate_config
      build
    end

    # Create a new TaskBuilder from a YAML file
    #
    # @param yaml_path [String] Path to the YAML configuration file
    # @return [TaskBuilder] A new task builder instance
    def self.from_yaml(yaml_path)
      cfg = YAML.load_file(yaml_path)
      new(config: cfg)
    end

    # Build the task handler class from the configuration
    #
    # @return [Class] The generated task handler class
    def build
      build_and_register_handler
    end

    # Validate the configuration against the schema
    #
    # @return [Boolean] True if the configuration is valid
    # @raise [InvalidTaskHandlerConfig] If the configuration is invalid
    def validate_config
      JSON::Validator.validate!(Tasker::Constants::YAML_SCHEMA, @config)
      validate_step_names
      true
    rescue JSON::Schema::ValidationError => e
      raise InvalidTaskHandlerConfig, "Invalid task handler configuration: #{e.message}"
    end

    private

    # Merge the base and environment-specific configurations
    #
    # @param config [Hash] The raw configuration hash
    # @return [Hash] The merged configuration
    def deep_merge_configs(config)
      # Get the base configuration
      base_config = Marshal.load(Marshal.dump(config))
      base_config.delete('environments')

      # Get environment-specific overrides if they exist
      env_config = config.dig('environments', Rails.env) if config.key?('environments')

      # If no environment-specific config, return base config
      return base_config unless env_config

      # Deep merge the configurations
      deep_merge(base_config, env_config)
    end

    # Deep merge two hashes with special handling for step templates
    #
    # @param base [Hash] The base hash
    # @param overrides [Hash] The hash to merge on top
    # @return [Hash] The merged hash
    def deep_merge(base, overrides)
      result = base.dup

      overrides.each do |key, value|
        result[key] = if result[key].is_a?(Hash) && value.is_a?(Hash)
                        deep_merge(result[key], value)
                      elsif key == 'step_templates'
                        # Special handling for step_templates to merge based on step name
                        merge_step_templates(result[key], value)
                      else
                        value
                      end
      end

      result
    end

    # Merge step templates from base and override configurations
    #
    # @param base_templates [Array<Hash>] The base templates array
    # @param override_templates [Array<Hash>] The override templates array
    # @return [Array<Hash>] The merged templates array
    def merge_step_templates(base_templates, override_templates)
      # Create a map of step templates by name for quick lookup
      template_map = base_templates.index_by do |template|
        template['name']
      end

      # Apply overrides to matching templates
      override_templates.each do |override|
        name = override['name']
        template_map[name] = deep_merge(template_map[name], override) if template_map.key?(name)
      end

      # Return the merged templates in their original order
      base_templates.map { |template| template_map[template['name']] }
    end

    # Validate that all step names are in the named_steps list if provided
    #
    # @return [void]
    # @raise [InvalidTaskHandlerConfig] If validation fails
    def validate_step_names
      return unless @config['named_steps']

      StepNameValidator.validate(@config)
    end

    # Service class to validate step names against named_steps list
    # Reduces complexity by organizing validation logic
    class StepNameValidator
      class << self
        # Validate all step names against named_steps list
        #
        # @param config [Hash] The configuration hash
        # @return [void]
        # @raise [InvalidTaskHandlerConfig] If validation fails
        def validate(config)
          named_steps_set = Set.new(config['named_steps'])

          config['step_templates'].each do |template|
            validate_template_name(template, named_steps_set)
            validate_single_dependency(template, named_steps_set)
            validate_multiple_dependencies(template, named_steps_set)
          end
        end

        private

        # Validate that template name is in named_steps list
        #
        # @param template [Hash] The step template
        # @param named_steps_set [Set] Set of valid step names
        # @return [void]
        # @raise [InvalidTaskHandlerConfig] If validation fails
        def validate_template_name(template, named_steps_set)
          return if named_steps_set.include?(template['name'])

          raise InvalidTaskHandlerConfig, "Step template name '#{template['name']}' is not in the named_steps list"
        end

        # Validate single dependency (depends_on_step) is in named_steps list
        #
        # @param template [Hash] The step template
        # @param named_steps_set [Set] Set of valid step names
        # @return [void]
        # @raise [InvalidTaskHandlerConfig] If validation fails
        def validate_single_dependency(template, named_steps_set)
          return unless template['depends_on_step']

          return if named_steps_set.include?(template['depends_on_step'])

          raise InvalidTaskHandlerConfig,
                "Dependency step '#{template['depends_on_step']}' is not in the named_steps list"
        end

        # Validate multiple dependencies (depends_on_steps) are in named_steps list
        #
        # @param template [Hash] The step template
        # @param named_steps_set [Set] Set of valid step names
        # @return [void]
        # @raise [InvalidTaskHandlerConfig] If validation fails
        def validate_multiple_dependencies(template, named_steps_set)
          return unless template['depends_on_steps']

          template['depends_on_steps'].each do |dep_step|
            unless named_steps_set.include?(dep_step)
              raise InvalidTaskHandlerConfig, "Dependency step '#{dep_step}' is not in the named_steps list"
            end
          end
        end
      end
    end

    # Build the handler class and register it
    #
    # @return [Class] The generated handler class
    def build_and_register_handler
      @handler_class = build_handler_class

      # Include the TaskHandler module
      @handler_class.include(Tasker::TaskHandler)

      # Define auto-generated constants
      define_constants

      # Register the handler
      @handler_class.register_handler(
        @config['name'],
        namespace_name: @config['namespace_name'] || :default,
        version: @config['version'] || '0.1.0',
        concurrent: @config.fetch('concurrent', true)
      )

      # Define step templates
      define_step_templates

      # Define schema method if schema is provided
      define_schema if @config['schema']

      @handler_class
    end

    # Build the handler class and set it in the proper namespace
    #
    # @return [Class] The new or existing handler class
    def build_handler_class
      # Create the class dynamically
      handler_module = Module.const_get(@config['module_namespace']) if @config['module_namespace']

      # Create the class if it doesn't exist yet
      if handler_module
        if handler_module.const_defined?(@config['task_handler_class'])
          @handler_class = handler_module.const_get(@config['task_handler_class'])
        else
          @handler_class = Class.new
          handler_module.const_set(@config['task_handler_class'], @handler_class)
        end
      elsif Object.const_defined?(@config['task_handler_class'])
        @handler_class = Object.const_get(@config['task_handler_class'])
      else
        @handler_class = Class.new
        Object.const_set(@config['task_handler_class'], @handler_class)
      end
      @handler_class
    end

    # Define constants for the handler class
    #
    # @return [void]
    def define_constants
      # Define the default dependent system constant if available
      if @config['default_dependent_system']
        default_system = @config['default_dependent_system']
        # Create a constant for the default system itself
        unless @handler_class.const_defined?(:DEFAULT_DEPENDENT_SYSTEM)
          @handler_class.const_set(:DEFAULT_DEPENDENT_SYSTEM,
                                   default_system)
        end
      end

      # Define named step constants
      return unless @config['named_steps']

      @handler_class.const_set(:NAMED_STEPS, @config['named_steps']) unless @handler_class.const_defined?(:NAMED_STEPS)
    end

    # Define step templates for the handler class
    #
    # @return [void]
    def define_step_templates
      StepTemplateDefiner.define_for_handler(@handler_class, @config)
    end

    # Service class to define step templates for handler classes
    # Reduces complexity by organizing template definition logic
    class StepTemplateDefiner
      class << self
        # Define step templates for a handler class
        #
        # @param handler_class [Class] The handler class
        # @param config [Hash] The configuration hash
        # @return [void]
        def define_for_handler(handler_class, config)
          templates = config['step_templates']
          default_system = config['default_dependent_system']

          handler_class.define_step_templates do |definer|
            templates.each do |template|
              process_template(definer, template, default_system)
            end
          end
        end

        private

        # Process a single template
        #
        # @param definer [Object] The template definer object
        # @param template [Hash] The template configuration
        # @param default_system [String] The default dependent system
        # @return [void]
        def process_template(definer, template, default_system)
          handler_class = resolve_handler_class(template)
          template['dependent_system'] ||= default_system
          handler_config = build_handler_config(template)

          define_single_template(definer, template, handler_class, handler_config)
        end

        # Resolve handler class from string name
        #
        # @param template [Hash] The template configuration
        # @return [Class] The handler class
        def resolve_handler_class(template)
          handler_class_name = template['handler_class']
          Object.const_get(handler_class_name)
        end

        # Build handler config object if needed
        #
        # @param template [Hash] The template configuration
        # @return [Object, nil] The handler config object
        def build_handler_config(template)
          return nil unless template['handler_config']

          config_data = template['handler_config']

          if config_data['type'] == 'api'
            build_api_config(config_data)
          else
            # Handle other config types as needed
            config_data
          end
        end

        # Build API configuration object
        #
        # @param config_data [Hash] The config data
        # @return [Tasker::StepHandler::Api::Config] The API config object
        def build_api_config(config_data)
          Tasker::StepHandler::Api::Config.new(
            url: config_data['url'],
            params: config_data['params'] || {},
            ssl: config_data['ssl'],
            headers: config_data['headers'],
            enable_exponential_backoff: config_data['enable_exponential_backoff'],
            retry_delay: config_data['retry_delay']
          )
        end

        # Define the step template using the definer
        #
        # @param definer [Object] The template definer object
        # @param template [Hash] The template configuration
        # @param handler_class [Class] The handler class
        # @param handler_config [Object] The handler config
        # @return [void]
        def define_single_template(definer, template, handler_class, handler_config)
          definer.define(
            dependent_system: template['dependent_system'],
            name: template['name'],
            description: template['description'] || template['name'],
            default_retryable: template.fetch('default_retryable', true),
            default_retry_limit: template.fetch('default_retry_limit', 3),
            skippable: template.fetch('skippable', false),
            handler_class: handler_class,
            depends_on_step: template['depends_on_step'],
            depends_on_steps: template['depends_on_steps'] || [],
            handler_config: handler_config
          )
        end
      end
    end

    # Define the schema method if a schema is provided
    #
    # @return [void]
    def define_schema
      schema_data = @config['schema']

      @handler_class.class_eval do
        define_method(:schema) do
          @schema ||= schema_data
        end
      end
    end
  end

  # Error raised when task handler configuration is invalid
  class InvalidTaskHandlerConfig < StandardError; end

  # A task handler that loads configuration from YAML
  #
  # ConfiguredTask provides a base class for task handlers that
  # load their configuration from YAML files.
  class ConfiguredTask < TaskBuilder
    include Tasker::TaskHandler

    class << self
      # Get the task name derived from the class name
      #
      # @return [String] The task name
      def task_name
        @task_name ||= to_s.underscore
      end

      # Get the path to the YAML configuration file
      #
      # @return [String] The path to the YAML file
      def yaml_path
        @yaml_path ||= Rails.root.join("config/#{Tasker::Configuration.configuration.engine.task_config_directory}/#{task_name}.yaml")
      end

      # Load the configuration from the YAML file
      #
      # @return [Hash] The loaded configuration
      def config
        @config ||= YAML.load_file(yaml_path)
      end
    end

    # Create a new ConfiguredTask
    #
    # @return [ConfiguredTask] A new configured task instance
    def initialize
      super(config: self.class.config)
    end
  end
end
