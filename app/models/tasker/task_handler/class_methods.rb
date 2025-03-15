# typed: false
# frozen_string_literal: true

require 'json-schema'

module Tasker
  module TaskHandler
    module ClassMethods
      class StepTemplateDefiner
        attr_reader :step_templates, :klass, :step_handler_class_map

        def initialize(klass)
          @klass = klass
          @step_templates = []
          @step_handler_class_map = {}
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

          @step_templates << Tasker::StepTemplate.new(
            dependent_system: dependent_system,
            name: name,
            description: description,
            default_retryable: default_retryable,
            default_retry_limit: default_retry_limit,
            skippable: skippable,
            handler_class: handler_class,
            depends_on_step: depends_on_step
          )
        end

        def register_class_map
          @step_templates.each do |template|
            @step_handler_class_map[template.name] = template.handler_class.to_s
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
      end

      def register_handler(name)
        Tasker::HandlerFactory.instance.register(name, self)
      end
    end
  end
end
