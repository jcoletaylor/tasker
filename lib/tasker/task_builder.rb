# frozen_string_literal: true

require 'yaml'
require 'json-schema'

module Tasker
  class TaskBuilder
    attr_reader :config, :handler_class

    # YAML schema for validating task handler configurations

    def initialize(config: {})
      @config = config
      validate_config
      build
    end

    def self.from_yaml(yaml_path)
      cfg = YAML.load_file(yaml_path)
      new(config: cfg)
    end

    def build
      build_and_register_handler
    end

    def validate_config
      JSON::Validator.validate!(Tasker::Constants::YAML_SCHEMA, @config)
      validate_step_names
      true
    rescue JSON::Schema::ValidationError => e
      raise InvalidTaskHandlerConfig, "Invalid task handler configuration: #{e.message}"
    end

    private

    def validate_step_names
      return unless @config['named_steps']

      # Create a set of named steps for quick lookups
      named_steps_set = Set.new(@config['named_steps'])

      # Check if all template names are in the named_steps list
      @config['step_templates'].each do |template|
        unless named_steps_set.include?(template['name'])
          raise InvalidTaskHandlerConfig, "Step template name '#{template['name']}' is not in the named_steps list"
        end

        # Check if dependency steps are also in the named_steps list
        if template['depends_on_step'] && named_steps_set.exclude?(template['depends_on_step'])
          raise InvalidTaskHandlerConfig,
                "Dependency step '#{template['depends_on_step']}' is not in the named_steps list"
        end

        next unless template['depends_on_steps']

        template['depends_on_steps'].each do |dep_step|
          unless named_steps_set.include?(dep_step)
            raise InvalidTaskHandlerConfig, "Dependency step '#{dep_step}' is not in the named_steps list"
          end
        end
      end
    end

    def build_and_register_handler
      # Create the class dynamically
      handler_module = Module.const_get(@config['module_namespace'])

      # Create the class if it doesn't exist yet
      if handler_module.const_defined?(@config['class_name'])
        @handler_class = handler_module.const_get(@config['class_name'])
      else
        @handler_class = Class.new
        handler_module.const_set(@config['class_name'], @handler_class)
      end

      # Include the TaskHandler module
      @handler_class.include(Tasker::TaskHandler)

      # Define auto-generated constants
      define_constants

      # Register the handler
      @handler_class.register_handler(
        @config['name'],
        concurrent: @config.fetch('concurrent', true)
      )

      # Define step templates
      define_step_templates

      # Define schema method if schema is provided
      define_schema if @config['schema']

      @handler_class
    end

    def define_constants
      # Define the default dependent system constant if available
      if @config['default_dependent_system']
        default_system = @config['default_dependent_system']
        # Create a constant for the default system itself
        @handler_class.const_set(:DEFAULT_DEPENDENT_SYSTEM, default_system) unless @handler_class.const_defined?(:DEFAULT_DEPENDENT_SYSTEM)
      end

      # Define named step constants
      return unless @config['named_steps']

      @handler_class.const_set(:NAMED_STEPS, @config['named_steps']) unless @handler_class.const_defined?(:NAMED_STEPS)
    end

    def define_step_templates
      templates = @config['step_templates']
      default_system = @config['default_dependent_system']

      @handler_class.define_step_templates do |definer|
        templates.each do |template|
          # Convert handler_class from string to actual class
          handler_class_name = template['handler_class']
          handler_class = Object.const_get(handler_class_name)

          # Use default dependent system if not specified in the template
          template['dependent_system'] ||= default_system

          # Create handler_config object if needed
          handler_config = nil
          if template['handler_config']
            config_data = template['handler_config']
            handler_config = if config_data['type'] == 'api'
                               Tasker::StepHandler::Api::Config.new(
                                 url: config_data['url'],
                                 params: config_data['params'] || {},
                                 ssl: config_data['ssl'],
                                 headers: config_data['headers'],
                                 enable_exponential_backoff: config_data['enable_exponential_backoff'],
                                 retry_delay: config_data['retry_delay']
                               )
                             else
                               # Handle other config types as needed
                               config_data
                             end
          end

          # Define the step template
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

    def define_schema
      schema_data = @config['schema']

      @handler_class.class_eval do
        define_method(:schema) do
          @schema ||= schema_data
        end
      end
    end
  end

  class InvalidTaskHandlerConfig < StandardError; end

  class ConfiguredTask < TaskBuilder
    include Tasker::TaskHandler

    def self.yaml_path
      raise NotImplementedError, 'Subclasses must implement yaml_path'
    end

    def initialize
      super(config: YAML.load_file(self.class.yaml_path))
    end
  end
end
