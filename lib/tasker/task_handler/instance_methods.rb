# typed: false
# frozen_string_literal: true

require 'json-schema'
require 'tasker/constants'
require 'tasker/types/step_sequence'
require 'tasker/events/event_payload_builder'
require_relative '../concerns/event_publisher'

module Tasker
  module TaskHandler
    # Instance methods for task handlers
    #
    # Provides the core task processing logic including the main execution loop,
    # step handling, and finalization. Delegates to orchestration components
    # for implementation details while maintaining proven loop-based approach.
    #
    # @author TaskHandler Authors
    module InstanceMethods
      include Tasker::Concerns::EventPublisher

      # List of attributes to pass from the task request to the task
      #
      # These are the attributes that will be copied from the task request
      # to the task when initializing a new task.
      #
      # @return [Array<Symbol>] List of attribute names
      TASK_REQUEST_ATTRIBUTES = %i[name context initiator reason source_system].freeze

      # Initialize a task
      #
      # Validates input and creates initial workflow steps via orchestration.
      #
      # @param task_request [TaskRequest] The task request to initialize
      # @return [Tasker::Task] The initialized task
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
      # This is the main entry point for processing a task. Uses proven
      # orchestration delegation patterns for reliable workflow execution.
      #
      # @param task [Tasker::Task] The task to handle
      # @return [void]
      def handle(task)
        start_task(task)

        # PROVEN APPROACH: Process steps iteratively until completion or error
        all_processed_steps = []

        loop do
          task.reload
          sequence = get_sequence(task)
          viable_steps = find_viable_steps(task, sequence)
          break if viable_steps.empty?

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

      # Handle execution of a single step
      #
      # This is a convenience method for testing that executes a single step.
      # Delegates to StepExecutor for consistent behavior.
      #
      # @param task [Tasker::Task] The task being processed
      # @param sequence [Tasker::Types::StepSequence] The step sequence
      # @param step [Tasker::WorkflowStep] The step to execute
      # @return [Tasker::WorkflowStep] The processed step
      def handle_one_step(task, sequence, step)
        step_executor.execute_single_step(task, sequence, step, self)
      end

      private

      # Memoized step executor for consistent reuse
      #
      # @return [Tasker::Orchestration::StepExecutor] The step executor instance
      def step_executor
        @step_executor ||= Tasker::Orchestration::StepExecutor.new
      end

      # Memoized task finalizer for consistent reuse
      #
      # @return [Tasker::Orchestration::TaskFinalizer] The task finalizer instance
      def task_finalizer
        @task_finalizer ||= Tasker::Orchestration::TaskFinalizer.new
      end

      # ================================================================
      # ASPIRATIONAL/FUTURE ENHANCEMENT METHODS
      #
      # These methods implement TaskWorkflowSummary-based intelligent
      # workflow processing. They are kept for future enhancement but
      # not currently used in core processing flows due to complexity
      # vs. value considerations.
      # ================================================================

      # FUTURE: Handle steps based on TaskWorkflowSummary recommendations
      #
      # This method uses the TaskWorkflowSummary view to intelligently process steps
      # with optimal processing strategies, eliminating the need for viable step discovery.
      #
      # @param summary [Tasker::TaskWorkflowSummary] The workflow summary with processing recommendations
      # @return [Array<Tasker::WorkflowStep>] Processed steps
      def handle_steps_via_summary(summary)
        # Get the recommended step IDs for processing
        step_ids = summary.next_steps_for_processing
        return [] if step_ids.empty?

        # Load steps with associations for processing
        steps = Tasker::WorkflowStep.where(workflow_step_id: step_ids)
        return [] if steps.empty?

        # Log processing strategy for observability
        Rails.logger.debug("TaskHandler: Processing #{steps.count} steps using #{summary.processing_strategy} strategy")

        # Execute steps using the recommended strategy
        task = summary.task
        sequence = get_sequence(task)
        execute_steps_with_strategy(task, sequence, steps, summary.processing_strategy)
      end

      # FUTURE: Execute steps using the processing strategy recommended by TaskWorkflowSummary
      #
      # @param task [Tasker::Task] The task being processed
      # @param sequence [Tasker::Types::StepSequence] The step sequence
      # @param steps [Array<Tasker::WorkflowStep>] Steps to execute
      # @param strategy [String] Processing strategy ('batch_parallel', 'small_parallel', 'sequential')
      # @return [Array<Tasker::WorkflowStep>] Processed steps
      def execute_steps_with_strategy(task, sequence, steps, strategy)
        # DELEGATE: Use the StepExecutor to handle all step execution logic
        # The strategy is informational - StepExecutor will use task handler settings for actual execution mode
        step_executor.execute_steps(task, sequence, steps)
      end

      # Find steps that are ready for execution
      #
      # This method finds workflow steps that are ready to be executed by checking
      # their state and dependencies. It's a proven pattern that works reliably.
      #
      # @param task [Tasker::Task] The task being processed
      # @param sequence [Tasker::Types::StepSequence] The step sequence
      # @return [Array<Tasker::WorkflowStep>] Steps ready for execution
      def find_viable_steps(task, sequence)
        Orchestration::ViableStepDiscovery.new.find_viable_steps(task, sequence)
      end

      # Handle execution of viable steps
      #
      # This method executes a collection of viable steps, delegating to the
      # StepExecutor for implementation details.
      #
      # @param task [Tasker::Task] The task being processed
      # @param sequence [Tasker::Types::StepSequence] The step sequence
      # @param viable_steps [Array<Tasker::WorkflowStep>] Steps ready for execution
      # @return [Array<Tasker::WorkflowStep>] Processed steps
      def handle_viable_steps(task, sequence, viable_steps)
        step_executor.execute_steps(task, sequence, viable_steps, self)
      end

      # Check if task is blocked by errors
      #
      # @param task [Tasker::Task] The task to check
      # @param sequence [Tasker::Types::StepSequence] The step sequence
      # @param processed_steps [Array<Tasker::WorkflowStep>] Recently processed steps
      # @return [Boolean] True if blocked by errors
      def blocked_by_errors?(task, sequence, processed_steps)
        task_finalizer.blocked_by_errors?(task, sequence, processed_steps)
      end

      # Finalize the task
      #
      # @param task [Tasker::Task] The task to finalize
      # @param sequence [Tasker::Types::StepSequence] The final step sequence
      # @param processed_steps [Array<Tasker::WorkflowStep>] All processed steps
      def finalize(task, sequence, processed_steps)
        # Call update_annotations hook before finalizing
        update_annotations(task, sequence, processed_steps) if respond_to?(:update_annotations)

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
