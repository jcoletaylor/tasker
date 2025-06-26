# frozen_string_literal: true

module Tasker
  module Orchestration
    # PluginIntegration provides shared access to TaskHandler plugin functionality
    #
    # This module extracts the plugin integration patterns from TaskHandler
    # and makes them available to orchestration components while preserving
    # the extensibility that makes Tasker valuable.
    #
    # Key methods preserved:
    # - get_step_handler: Access to step handler plugins
    # - establish_step_dependencies_and_defaults: Extensibility hook
    # - update_annotations: Extensibility hook
    # - schema validation: Context validation hook
    module PluginIntegration
      # Get a step handler for a specific step
      #
      # This method integrates with the TaskHandler plugin system to get
      # the appropriate handler for a step.
      #
      # @param step [Tasker::WorkflowStep] The step to get a handler for
      # @param task_handler [Object] The task handler instance
      # @return [Object] The step handler
      # @raise [Tasker::ProceduralError] If no handler is registered for the step
      def get_step_handler_from_task_handler(step, task_handler)
        unless task_handler.step_handler_class_map[step.name]
          raise(Tasker::ProceduralError,
                "No registered class for #{step.name}")
        end

        handler_config = task_handler.step_handler_config_map[step.name]
        handler_class = task_handler.step_handler_class_map[step.name].to_s.camelize.constantize

        return handler_class.new if handler_config.nil?

        handler_class.new(config: handler_config)
      end

      # Get the step sequence for a task using task handler
      #
      # This delegates to the task handler's get_sequence method which handles
      # step template creation and dependency establishment.
      #
      # @param task [Tasker::Task] The task
      # @param task_handler [Object] The task handler instance
      # @return [Tasker::Types::StepSequence] The step sequence
      def get_sequence_for_task(task, task_handler)
        task_handler.get_sequence(task)
      end

      # Establish step dependencies and defaults using task handler hook
      #
      # @param task [Tasker::Task] The task being processed
      # @param steps [Array<Tasker::WorkflowStep>] The steps to establish dependencies for
      # @param task_handler [Object] The task handler instance
      def establish_step_dependencies_and_defaults_via_handler(task, steps, task_handler)
        # Call the task handler's hook method if it exists
        return unless task_handler.respond_to?(:establish_step_dependencies_and_defaults)

        task_handler.establish_step_dependencies_and_defaults(task, steps)
      end

      # Update annotations using task handler hook
      #
      # @param task [Tasker::Task] The task being processed
      # @param sequence [Tasker::Types::StepSequence] The sequence of steps
      # @param steps [Array<Tasker::WorkflowStep>] The processed steps
      # @param task_handler [Object] The task handler instance
      def update_annotations_via_handler(task, sequence, steps, task_handler)
        return unless task_handler.respond_to?(:update_annotations)

        task_handler.update_annotations(task, sequence, steps)
      end

      # Validate context using task handler schema
      #
      # @param context [Hash] The context to validate
      # @param task_handler [Object] The task handler with schema
      # @return [Array<String>] Validation errors, if any
      def validate_context_via_handler(context, task_handler)
        return [] unless task_handler.respond_to?(:schema) && task_handler.schema

        data = context.to_hash.deep_symbolize_keys
        JSON::Validator.fully_validate(task_handler.schema, data, strict: true, insert_defaults: true)
      end

      # Check if task handler supports concurrent processing
      #
      # This checks the task handler's concurrent processing configuration
      # to determine the appropriate processing mode.
      #
      # @param task_handler [Object] The task handler instance
      # @return [Boolean] True if concurrent processing is enabled
      def supports_concurrent_processing?(_task_handler)
        true
      end

      # Get task handler instance for a task
      #
      # @param task [Tasker::Task] The task
      # @return [Object] The task handler instance
      def get_task_handler_for_task(task)
        handler_factory = Tasker::HandlerFactory.instance
        handler_factory.get(
          task.name,
          namespace_name: task.named_task.task_namespace.name,
          version: task.named_task.version
        )
      end

      # Get task handler class for a task name
      #
      # This provides access to the handler class without instantiation.
      #
      # @param task_name [String] The task name
      # @return [Class] The task handler class
      def get_task_handler_class(task_name)
        handler_factory = Tasker::HandlerFactory.instance
        handler_factory.handler_class_for(task_name)
      end
    end
  end
end
