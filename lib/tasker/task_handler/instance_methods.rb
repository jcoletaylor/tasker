# typed: false
# frozen_string_literal: true

require 'json-schema'
require 'tasker/lifecycle_events'
require 'tasker/events/event_payload_builder'

module Tasker
  module TaskHandler
    # Instance methods for task handlers
    #
    # This module provides the core task handling functionality including
    # task initialization, step processing, error handling, and workflow
    # execution logic.
    module InstanceMethods
      # Initialize a new task from a task request
      #
      # Creates a task record, validates the context against the schema,
      # and enqueues the task for processing.
      #
      # @param task_request [Tasker::Types::TaskRequest] The task request
      # @return [Tasker::Task] The created task
      def initialize_task!(task_request)
        task = nil
        context_errors = validate_context(task_request.context)
        if context_errors.length.positive?
          task = Tasker::Task.from_task_request(task_request)
          context_errors.each do |error|
            task.errors.add(:context, error)
          end
          Tasker::LifecycleEvents.fire(
            Tasker::LifecycleEvents::Events::Task::INITIALIZE,
            { task_name: task_request.name, status: 'error', errors: context_errors }
          )
          return task
        end
        Tasker::Task.transaction do
          task = Tasker::Task.create_with_defaults!(task_request)
          get_sequence(task)
        end
        Tasker::LifecycleEvents.fire(
          Tasker::LifecycleEvents::Events::Task::INITIALIZE,
          { task_id: task.task_id, task_name: task.name, status: 'success' }
        )
        enqueue_task(task)
        task
      end

      # Get the step sequence for a task
      #
      # Retrieves all workflow steps for the task and establishes their dependencies.
      #
      # @param task [Tasker::Task] The task to get the sequence for
      # @return [Tasker::Types::StepSequence] The sequence of workflow steps
      def get_sequence(task)
        steps = Tasker::WorkflowStep.get_steps_for_task(task, step_templates)
        establish_step_dependencies_and_defaults(task, steps)
        Tasker::Types::StepSequence.new(steps: steps)
      end

      # Start a task's execution
      #
      # Updates the task status to IN_PROGRESS and fires the appropriate event.
      #
      # @param task [Tasker::Task] The task to start
      # @return [Boolean] True if the task was started successfully
      # @raise [Tasker::ProceduralError] If the task is already complete or not pending
      def start_task(task)
        raise(Tasker::ProceduralError, "task already complete for task #{task.task_id}") if task.complete

        unless task.status == Tasker::Constants::TaskStatuses::PENDING
          raise(Tasker::ProceduralError,
                "task is not pending for task #{task.task_id}, status is #{task.status}")
        end

        task.context = ActiveSupport::HashWithIndifferentAccess.new(task.context)

        # Use state machine to transition task to in_progress
        task.state_machine.transition_to!(Tasker::Constants::TaskStatuses::IN_PROGRESS)

        Tasker::LifecycleEvents.fire(
          Tasker::LifecycleEvents::Events::Task::START,
          { task_id: task.task_id, task_name: task.name, task_context: task.context }
        )

        true
      end

      # Handle a task's execution
      #
      # This is the main entry point for processing a task. It starts the task,
      # processes viable steps iteratively until completion or error, and then finalizes.
      #
      # @param task [Tasker::Task] The task to handle
      # @return [void]
      def handle(task)
        start_task(task)

        # Process steps recursively until no more viable steps are found
        all_processed_steps = []

        loop do
          # Get the latest sequence with up-to-date step statuses
          task.reload
          sequence = get_sequence(task)

          # Find viable steps according to DAG traversal
          # Force a fresh load of all steps, including children of completed steps
          viable_steps = find_viable_steps(task, sequence)

          # Log the viable steps found
          if viable_steps.any?
            step_names = viable_steps.map(&:name)
            Tasker::LifecycleEvents.fire(
              Tasker::Constants::ObservabilityEvents::Step::FIND_VIABLE,
              {
                task_id: task.task_id,
                step_names: step_names.join(', '),
                count: viable_steps.size
              }
            )
          end

          # If no viable steps found, we're done
          break if viable_steps.empty?

          # Process the viable steps
          processed_in_this_round = handle_viable_steps(task, sequence, viable_steps)
          all_processed_steps.concat(processed_in_this_round)

          # Check if any errors occurred that would block further progress
          break if blocked_by_errors?(task, sequence, processed_in_this_round)
        end

        # Get final sequence after all processing
        final_sequence = get_sequence(task)

        # Finalize the task
        finalize(task, final_sequence, all_processed_steps)
      end

      # Find viable steps that can be executed
      #
      # Checks all unfinished steps to find those that are ready for processing
      # based on their dependencies and current state.
      #
      # @param task [Tasker::Task] The task being processed
      # @param sequence [Tasker::Types::StepSequence] The sequence of steps
      # @return [Array<Tasker::WorkflowStep>] The viable steps
      def find_viable_steps(task, sequence)
        unfinished_steps = sequence.steps.reject { |step| step.processed || step.in_process }

        viable_steps = []
        unfinished_steps.each do |step|
          # Reload to get latest status
          fresh_step = Tasker::WorkflowStep.find(step.workflow_step_id)

          # Skip if step is now processed or in process
          next if fresh_step.processed || fresh_step.in_process

          # Check if step is viable with latest DB state
          viable_steps << fresh_step if Tasker::WorkflowStep.is_step_viable?(fresh_step, task)
        end

        viable_steps
      end

      # Handle a single workflow step
      #
      # Processes a step with proper span management, error handling,
      # and retry logic.
      #
      # @param task [Tasker::Task] The task being processed
      # @param sequence [Tasker::Types::StepSequence] The sequence of steps
      # @param step [Tasker::WorkflowStep] The step to handle
      # @return [Tasker::WorkflowStep] The processed step
      def handle_one_step(task, sequence, step)
        # Use the lifecycle events to handle a step with proper span management
        span_context = build_step_span_context(task, step)

        # This will create a span that's properly connected to the parent task span
        Tasker::LifecycleEvents.fire_with_span(
          Tasker::Constants::ObservabilityEvents::Step::HANDLE,
          span_context.merge(attempt: step.attempts.to_i + 1)
        ) do
          handler = get_step_handler(step)
          step.attempts ||= 0

          begin
            # Transition step to IN_PROGRESS before execution
            # Use state machine to transition step to in_progress
            step.state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS)

            # Now execute the step
            handler.handle(task, sequence, step)
            handle_step_success(step, span_context)
          rescue StandardError => e
            handle_step_error(step, e, span_context)
          end

          # Common post-handling logic
          step.attempts += 1
          step.last_attempted_at = Time.zone.now

          # Check for retry or max retries reached
          handle_retry_events(step, span_context) if step.status == Tasker::Constants::WorkflowStepStatuses::ERROR

          step.save!
          step
        end
      end

      private

      # Build context data for step spans
      #
      # @param task [Tasker::Task] The task being processed
      # @param step [Tasker::WorkflowStep] The step being handled
      # @return [Hash] The span context data
      def build_step_span_context(task, step)
        {
          span_name: "step.#{step.name}",
          task_id: task.task_id,
          step_id: step.workflow_step_id,
          step_name: step.name,
          step_inputs: step.inputs
        }
      end

      # Handle successful completion of a step
      #
      # @param step [Tasker::WorkflowStep] The step that succeeded
      # @param span_context [Hash] The span context data
      # @return [void]
      def handle_step_success(step, span_context)
        step.processed = true
        step.processed_at = Time.zone.now
        # Use state machine to transition step to complete
        step.state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::COMPLETE)

        # Use EventPayloadBuilder for standardized payload
        payload = Tasker::Events::EventPayloadBuilder.build_step_payload(
          step,
          event_type: :completed,
          additional_context: span_context
        )

        Tasker::LifecycleEvents.fire(
          Tasker::Constants::StepEvents::COMPLETED,
          payload
        )
      end

      # Handle error during step processing
      #
      # @param step [Tasker::WorkflowStep] The step that encountered an error
      # @param error [StandardError] The error that occurred
      # @param span_context [Hash] The span context data
      # @return [void]
      def handle_step_error(step, error, span_context)
        step.processed = false
        step.processed_at = nil
        # Use state machine to transition step to error
        step.state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::ERROR)
        step.results ||= {}
        step.results = step.results.merge(error: error.to_s, backtrace: error.backtrace.join("\n"))

        # Use EventPayloadBuilder for standardized payload
        payload = Tasker::Events::EventPayloadBuilder.build_step_payload(
          step,
          event_type: :failed,
          additional_context: span_context.merge(
            error: error.to_s,
            error_message: error.message,
            exception_object: error,
            backtrace: error.backtrace.join("\n")
          )
        )

        Tasker::LifecycleEvents.fire(
          Tasker::Constants::StepEvents::FAILED,
          payload
        )
      end

      # Handle retry-related events for a step
      #
      # @param step [Tasker::WorkflowStep] The step being retried
      # @param span_context [Hash] The span context data
      # @return [void]
      def handle_retry_events(step, span_context)
        # Record if max retries reached
        if step.attempts >= step.retry_limit
          # Use EventPayloadBuilder for standardized payload
          payload = Tasker::Events::EventPayloadBuilder.build_step_payload(
            step,
            event_type: :max_retries_reached,
            additional_context: span_context.merge(
              attempts: step.attempts,
              retry_limit: step.retry_limit
            )
          )

          Tasker::LifecycleEvents.fire(
            Tasker::Constants::ObservabilityEvents::Step::MAX_RETRIES_REACHED,
            payload
          )
          return
        end

        # Record a retry event if this is a retry attempt (attempts > 0)
        # Note: attempts is incremented before this method is called
        return unless step.attempts > 1

        # Use EventPayloadBuilder for standardized payload
        payload = Tasker::Events::EventPayloadBuilder.build_step_payload(
          step,
          event_type: :retry,
          additional_context: span_context.merge(
            attempt: step.attempts
          )
        )

        Tasker::LifecycleEvents.fire(
          Tasker::Constants::StepEvents::RETRY_REQUESTED,
          payload
        )
      end

      # Handle a set of viable steps either concurrently or sequentially
      #
      # @param task [Tasker::Task] The task being processed
      # @param sequence [Tasker::Types::StepSequence] The sequence of steps
      # @param steps [Array<Tasker::WorkflowStep>] The viable steps to handle
      # @return [Array<Tasker::WorkflowStep>] The processed steps
      def handle_viable_steps(task, sequence, steps)
        # Delegate to the appropriate handler based on concurrent processing setting
        if respond_to?(:use_concurrent_processing?) && use_concurrent_processing?
          handle_viable_steps_concurrently(task, sequence, steps)
        else
          handle_viable_steps_sequentially(task, sequence, steps)
        end
      end

      # Handle viable steps concurrently using futures
      #
      # @param task [Tasker::Task] The task being processed
      # @param sequence [Tasker::Types::StepSequence] The sequence of steps
      # @param steps [Array<Tasker::WorkflowStep>] The viable steps to handle
      # @return [Array<Tasker::WorkflowStep>] The processed steps
      def handle_viable_steps_concurrently(task, sequence, steps)
        # Create an array of futures and processed steps
        futures = []
        processed_steps = Concurrent::Array.new

        # Create a future for each step
        steps.each do |step|
          # Use Concurrent::Future to process each step asynchronously
          future = Concurrent::Future.execute do
            handle_one_step(task, sequence, step)
          end

          futures << future
        end

        # Wait for all futures to complete
        futures.each do |future|
          # Wait for the future to complete (with a reasonable timeout)

          # 30 second timeout to prevent indefinite hanging
          result = future.value(30)
          processed_steps << result if result
        rescue StandardError => e
          Rails.logger.error("Error processing step concurrently: #{e.message}")
        end

        # Update annotations for this batch
        update_annotations(task, sequence, processed_steps)

        processed_steps.to_a
      end

      # Handle viable steps sequentially
      #
      # @param task [Tasker::Task] The task being processed
      # @param sequence [Tasker::Types::StepSequence] The sequence of steps
      # @param steps [Array<Tasker::WorkflowStep>] The viable steps to handle
      # @return [Array<Tasker::WorkflowStep>] The processed steps
      def handle_viable_steps_sequentially(task, sequence, steps)
        processed_steps = []

        # Process each step one at a time
        steps.each do |step|
          processed_step = handle_one_step(task, sequence, step)
          processed_steps << processed_step
        end

        # Update annotations for this batch
        update_annotations(task, sequence, processed_steps)

        processed_steps
      end

      # Finalize a task after processing
      #
      # Determines whether a task is complete, should be re-enqueued,
      # or has encountered errors that prevent completion.
      #
      # @param task [Tasker::Task] The task being finalized
      # @param sequence [Tasker::Types::StepSequence] The sequence of steps
      # @param steps [Array<Tasker::WorkflowStep>] The steps that were processed
      # @return [void]
      def finalize(task, sequence, steps)
        # Use EventPayloadBuilder for task finalization event
        payload = Tasker::Events::EventPayloadBuilder.build_task_payload(
          task,
          event_type: :finalize
        )

        Tasker::LifecycleEvents.fire(
          Tasker::Constants::ObservabilityEvents::Task::FINALIZE,
          payload
        )

        return if blocked_by_errors?(task, sequence, steps)

        step_group = StepGroup.build(task, sequence, steps)

        if step_group.complete?
          # Use state machine to transition task to complete
          task.state_machine.transition_to!(Tasker::Constants::TaskStatuses::COMPLETE)

          # Use EventPayloadBuilder for task completion event
          completion_payload = Tasker::Events::EventPayloadBuilder.build_task_payload(
            task,
            event_type: :completed
          )

          Tasker::LifecycleEvents.fire(
            Tasker::Constants::TaskEvents::COMPLETED,
            completion_payload
          )
          return
        end

        # if we have steps that still need to be completed and in valid states
        # set the status of the task back to pending, update it,
        # and re-enqueue the task for processing
        if step_group.pending?
          # Request re-processing (state machine will handle if already pending)
          task.state_machine.transition_to!(Tasker::Constants::TaskStatuses::PENDING)
          enqueue_task(task)
          return
        end

        # if we reach the end and have not re-enqueued the task
        # then we mark it complete since none of the above proved true
        # Request completion (state machine will handle if already complete)
        task.state_machine.transition_to!(Tasker::Constants::TaskStatuses::COMPLETE)

        # Use EventPayloadBuilder for task completion event
        completion_payload = Tasker::Events::EventPayloadBuilder.build_task_payload(
          task,
          event_type: :completed
        )

        Tasker::LifecycleEvents.fire(
          Tasker::Constants::TaskEvents::COMPLETED,
          completion_payload
        )
      end

      # Check if any steps have exceeded their retry limit
      #
      # @param error_steps [Array<Tasker::WorkflowStep>] Steps in error state
      # @return [Boolean] True if any step has too many attempts
      def too_many_attempts?(error_steps)
        too_many_attempts_steps = []
        error_steps.each do |err_step|
          too_many_attempts_steps << err_step if err_step.attempts.positive? && !err_step.retryable
          too_many_attempts_steps << err_step if err_step.attempts >= err_step.retry_limit
        end
        too_many_attempts_steps.length.positive?
      end

      # Check if the task is blocked by errors
      #
      # @param task [Tasker::Task] The task being processed
      # @param sequence [Tasker::Types::StepSequence] The sequence of steps
      # @param steps [Array<Tasker::WorkflowStep>] The steps that were processed
      # @return [Boolean] True if the task is blocked by errors
      def blocked_by_errors?(task, sequence, steps)
        # how many steps in this round are in an error state before, and based on
        # being processed in this round of handling, is it still in an error state
        error_steps = get_error_steps(steps, sequence)
        # if there are no steps in error still, then move on to the rest of the checks
        # if there are steps in error still, then we need to see if we have tried them
        if error_steps.length.positive?
          if too_many_attempts?(error_steps)
            # Transition to error state (state machine will prevent invalid transitions)
            task.state_machine.transition_to!(Tasker::Constants::TaskStatuses::ERROR)

            # Use EventPayloadBuilder for task error event
            error_payload = Tasker::Events::EventPayloadBuilder.build_task_payload(
              task,
              event_type: :failed,
              additional_context: {
                error_steps: error_steps.map(&:name).join(', '),
                error_step_results: error_steps.map do |step|
                  { step_id: step.workflow_step_id, step_name: step.name, step_results: step.results }
                end
              }
            )

            Tasker::LifecycleEvents.fire(
              Tasker::Constants::TaskEvents::FAILED,
              error_payload
            )
            return true
          end

          # Request retry by transitioning to pending (state machine will handle if already pending)
          task.state_machine.transition_to!(Tasker::Constants::TaskStatuses::PENDING)
          enqueue_task(task)
          return true
        end
        false
      end

      # Get a step handler for a specific step
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

      # Get steps that are still in error state
      #
      # @param steps [Array<Tasker::WorkflowStep>] The processed steps
      # @param sequence [Tasker::Types::StepSequence] The sequence of steps
      # @return [Array<Tasker::WorkflowStep>] Steps still in error state
      def get_error_steps(steps, sequence)
        error_steps = []
        sequence.steps.each do |step|
          # if in the original sequence this was an error
          # we need to see if the updated steps are still in error
          next unless step.status == Tasker::Constants::WorkflowStepStatuses::ERROR

          processed_step =
            steps.find do |s|
              s.workflow_step_id == step.workflow_step_id
            end
          # no updated step was found to change our mind
          # about whether it was in error before, so true, still in error
          if processed_step.nil?
            error_steps << step
            next
          end

          # was the processed step in error still
          error_steps << step if processed_step.status == Tasker::Constants::WorkflowStepStatuses::ERROR
        end
        error_steps
      end

      # Enqueue a task for processing
      #
      # @param task [Tasker::Task] The task to enqueue
      # @return [void]
      def enqueue_task(task)
        # Use EventPayloadBuilder for task enqueue event
        payload = Tasker::Events::EventPayloadBuilder.build_task_payload(
          task,
          event_type: :enqueue,
          additional_context: {
            task_context: task.context
          }
        )

        Tasker::LifecycleEvents.fire(
          Tasker::Constants::ObservabilityEvents::Task::ENQUEUE,
          payload
        )
        Tasker::TaskRunnerJob.perform_later(task.task_id)
      end

      # Establish step dependencies and defaults
      #
      # This is a hook method that can be overridden by implementing classes.
      #
      # @param task [Tasker::Task] The task being processed
      # @param steps [Array<Tasker::WorkflowStep>] The steps to establish dependencies for
      # @return [void]
      def establish_step_dependencies_and_defaults(task, steps); end

      # Update annotations based on processed steps
      #
      # This is a hook method that can be overridden by implementing classes.
      #
      # @param task [Tasker::Task] The task being processed
      # @param sequence [Tasker::Types::StepSequence] The sequence of steps
      # @param steps [Array<Tasker::WorkflowStep>] The processed steps
      # @return [void]
      def update_annotations(task, sequence, steps); end

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
