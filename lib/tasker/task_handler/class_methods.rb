# typed: false
# frozen_string_literal: true

require 'json-schema'
require 'concurrent'

module Tasker
  module TaskHandler
    module ClassMethods
      class StepTemplateDefiner
        attr_reader :step_templates, :klass, :step_handler_class_map, :step_handler_config_map

        def initialize(klass)
          @klass = klass
          @step_templates = []
          @step_handler_class_map = {}
          @step_handler_config_map = {}
        end

        def define(**kwargs)
          dependent_system = kwargs.fetch(:dependent_system, Tasker::Constants::UNKNOWN)
          name = kwargs.fetch(:name)
          handler_class = kwargs.fetch(:handler_class)
          description = kwargs.fetch(:description, name)
          default_retryable = kwargs.fetch(:default_retryable, true)
          default_retry_limit = kwargs.fetch(:default_retry_limit, 3)
          skippable = kwargs.fetch(:skippable, false)
          depends_on_step = kwargs.fetch(:depends_on_step, nil)
          depends_on_steps = kwargs.fetch(:depends_on_steps, [])
          handler_config = kwargs.fetch(:handler_config, nil)

          @step_templates << Tasker::Types::StepTemplate.new(
            dependent_system: dependent_system,
            name: name,
            description: description,
            default_retryable: default_retryable,
            default_retry_limit: default_retry_limit,
            skippable: skippable,
            handler_class: handler_class,
            depends_on_step: depends_on_step,
            depends_on_steps: depends_on_steps,
            handler_config: handler_config
          )
        end

        def register_class_map
          @step_templates.each do |template|
            @step_handler_class_map[template.name] = template.handler_class.to_s
            @step_handler_config_map[template.name] = template.handler_config
          end
        end
      end

      def define_step_templates
        definer = StepTemplateDefiner.new(self)
        yield(definer)
        definer.klass.define_method(:step_templates) do
          definer.step_templates
        end
        definer.register_class_map
        definer.klass.define_method(:step_handler_class_map) do
          definer.step_handler_class_map
        end
        definer.klass.define_method(:step_handler_config_map) do
          definer.step_handler_config_map
        end
      end

      # Simple register_handler method that enables or disables concurrent processing
      # using Concurrent::Future for step execution
      #
      # @param name [String, Symbol] The name to register the handler under
      # @param concurrent [Boolean] Whether to use concurrent processing (default: true)
      # @return [void]
      def register_handler(name, concurrent: true)
        # Set a flag indicating whether to use concurrent processing
        class_variable_set(:@@use_concurrent_processing, concurrent)

        # Define a method to check if concurrent processing is enabled
        define_method(:use_concurrent_processing?) do
          self.class.class_variable_get(:@@use_concurrent_processing)
        end

        # Register the handler with the factory
        Tasker::HandlerFactory.instance.register(name, self)
      end
    end
  end
end
