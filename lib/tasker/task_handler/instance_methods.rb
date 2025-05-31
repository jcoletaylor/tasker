# typed: false
# frozen_string_literal: true

require 'json-schema'
require 'tasker/lifecycle_events'
require 'tasker/events/event_payload_builder'
require_relative '../concerns/lifecycle_event_helpers'

module Tasker
  module TaskHandler
    # Instance methods for task handlers
    #
    # This module provides the core task handling functionality including
    # task initialization, step processing, error handling, and workflow
    # execution logic.
    #
    # This implementation uses the proven loop-based approach while delegating
    # actual implementation to orchestration classes for better observability.
    module InstanceMethods
      include Tasker::Concerns::LifecycleEventHelpers

      # Initialize a new task from a task request
      #
      # Creates a task record, validates the context against the schema,
      # and enqueues the task for processing.
      #
      # @param task_request [Tasker::Types::TaskRequest] The task request
      # @return [Tasker::Task] The created task
      def initialize_task!(task_request)
        # Delegate to orchestration system
        Tasker::Orchestration::TaskInitializer.initialize_task!(task_request, self)
      end

      # Get the step sequence for a task
      #
      # Retrieves all workflow steps for the task and establishes their dependencies.
      # Delegates to StepSequenceFactory for implementation + observability events.
      #
      # @param task [Tasker::Task] The task to get the sequence for
      # @return [Tasker::Types::StepSequence] The sequence of workflow steps
      def get_sequence(task)
        # Delegate to orchestration system for implementation + events
        Tasker::Orchestration::StepSequenceFactory.get_sequence(task, self)
      end

      # Start a task's execution
      #
      # Updates the task status to IN_PROGRESS and fires the appropriate event.
      #
      # @param task [Tasker::Task] The task to start
      # @return [Boolean] True if the task was started successfully
      # @raise [Tasker::ProceduralError] If the task is already complete or not pending
      def start_task(task)
        # Delegate to orchestration system
        Tasker::Orchestration::TaskInitializer.start_task!(task)
      end

      # Handle a task's execution
      #
      # This is the main entry point for processing a task. Uses the proven
      # loop-based approach while delegating implementation to orchestration classes.
      #
      # @param task [Tasker::Task] The task to handle
      # @return [void]
      def handle(task)
        start_task(task)

        # PROVEN APPROACH: Process steps iteratively until completion or error
        all_processed_steps = []

        loop do
          task.reload

          # DELEGATE: Get sequence via StepSequenceFactory (fires events internally)
          sequence = get_sequence(task)

          # DELEGATE: Find viable steps via ViableStepDiscovery (fires events internally)
          viable_steps = find_viable_steps(task, sequence)

          break if viable_steps.empty?

          # DELEGATE: Process steps via StepExecutor (preserves concurrency + fires events)
          processed_steps = handle_viable_steps(task, sequence, viable_steps)
          all_processed_steps.concat(processed_steps)

          break if blocked_by_errors?(task, sequence, processed_steps)
        end

        # DELEGATE: Finalize via TaskFinalizer (fires events internally)
        finalize(task, get_sequence(task), all_processed_steps)
      end

      # Establish step dependencies and defaults
      #
      # This is a hook method that can be overridden by implementing classes.
      # This method is public so that orchestration components can call it.
      #
      # @param task [Tasker::Task] The task being processed
      # @param steps [Array<Tasker::WorkflowStep>] The steps to establish dependencies for
      # @return [void]
      def establish_step_dependencies_and_defaults(task, steps); end

      # Update annotations based on processed steps
      #
      # This is a hook method that can be overridden by implementing classes.
      # This method is public so that orchestration components can call it.
      #
      # @param task [Tasker::Task] The task being processed
      # @param sequence [Tasker::Types::StepSequence] The sequence of steps
      # @param steps [Array<Tasker::WorkflowStep>] The processed steps
      # @return [void]
      def update_annotations(task, sequence, steps); end

      # Get a step handler for a specific step
      #
      # This method is public so that orchestration components can access step handlers.
      #
      # @param step [Tasker::WorkflowStep] The step to get a handler for
      # @return [Object] The step handler
      # @raise [Tasker::ProceduralError] If no handler is registered for the step
      def get_step_handler(step)
        raise(Tasker::ProceduralError, "No registered class for #{step.name}") unless step_handler_class_map[step.name]

        handler_config = step_handler_config_map[step.name]
        handler_class = step_handler_class_map[step.name].to_s.camelize.constantize

        return handler_class.new if handler_config.nil?

        handler_class.new(config: handler_config)
      end

      private

      # Find viable steps for execution
      #
      # Delegates to ViableStepDiscovery but uses direct method call (not events)
      # for the proven loop approach.
      #
      # @param task [Tasker::Task] The task to find steps for
      # @param sequence [Tasker::Types::StepSequence] The step sequence
      # @return [Array<Tasker::WorkflowStep>] Array of viable steps
      def find_viable_steps(task, sequence)
        # Direct delegation - no event indirection needed for core loop
        Tasker::Orchestration::ViableStepDiscovery.new.find_viable_steps(task, sequence)
      end

      # Handle execution of viable steps
      #
      # Delegates to StepExecutor which preserves concurrent processing and fires events.
      #
      # @param task [Tasker::Task] The task being processed
      # @param sequence [Tasker::Types::StepSequence] The step sequence
      # @param viable_steps [Array<Tasker::WorkflowStep>] Steps ready for execution
      # @return [Array<Tasker::WorkflowStep>] Processed steps
      def handle_viable_steps(task, sequence, viable_steps)
        step_executor = Tasker::Orchestration::StepExecutor.new
        step_executor.execute_steps(task, sequence, viable_steps, self)
      end

      # Check if task is blocked by errors
      #
      # @param task [Tasker::Task] The task to check
      # @param sequence [Tasker::Types::StepSequence] The step sequence
      # @param processed_steps [Array<Tasker::WorkflowStep>] Recently processed steps
      # @return [Boolean] True if blocked by errors
      def blocked_by_errors?(task, sequence, processed_steps)
        task_finalizer = Tasker::Orchestration::TaskFinalizer.new
        task_finalizer.blocked_by_errors?(task, sequence, processed_steps)
      end

      # Finalize the task
      #
      # @param task [Tasker::Task] The task to finalize
      # @param sequence [Tasker::Types::StepSequence] The final step sequence
      # @param processed_steps [Array<Tasker::WorkflowStep>] All processed steps
      def finalize(task, sequence, processed_steps)
        task_finalizer = Tasker::Orchestration::TaskFinalizer.new

        # Call update_annotations hook before finalizing
        if self.respond_to?(:update_annotations)
          self.update_annotations(task, sequence, processed_steps)
        end

        task_finalizer.finalize_task_with_steps(task, sequence, processed_steps)
      end

      # Get the schema for validating task context
      #
      # This is a hook method that can be overridden by implementing classes.
      #
      # @return [Hash, nil] The JSON schema for task context validation
      def schema
        nil
      end

      # Validate a task context against the schema
      #
      # @param context [Hash] The context to validate
      # @return [Array<String>] Validation errors, if any
      def validate_context(context)
        return [] unless schema

        data = context.to_hash.deep_symbolize_keys
        JSON::Validator.fully_validate(schema, data, strict: true, insert_defaults: true)
      end
    end
  end
end
