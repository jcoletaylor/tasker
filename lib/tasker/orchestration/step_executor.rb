# frozen_string_literal: true

require 'dry/events'
require 'concurrent'

module Tasker
  module Orchestration
    # StepExecutor handles the execution of workflow steps via state machine transitions
    #
    # This class extracts the step execution logic from TaskHandler::InstanceMethods
    # and makes it event-driven, responding to viable step discovery events.
    class StepExecutor
      include Dry::Events::Publisher[:step_executor]
      include Tasker::Concerns::IdempotentStateTransitions

      # Register events that this component publishes
      register_event(Tasker::Constants::WorkflowEvents::STEPS_EXECUTION_STARTED)
      register_event(Tasker::Constants::WorkflowEvents::STEPS_EXECUTION_COMPLETED)
      register_event(Tasker::Constants::WorkflowEvents::STEP_EXECUTION_FAILED)

      class << self
        # Subscribe to workflow events for step execution
        #
        # @param bus [Tasker::Events::Bus] The event bus to subscribe to
        def subscribe_to_workflow_events(bus = nil)
          event_bus = bus || Tasker::LifecycleEvents.bus
          executor = new

          # Subscribe to viable steps discovered events
          event_bus.subscribe(Tasker::Constants::WorkflowEvents::VIABLE_STEPS_DISCOVERED) do |event|
            executor.execute_viable_steps(event)
          end

          Rails.logger.info('Tasker::Orchestration::StepExecutor subscribed to workflow events')
        end
      end

      # Execute viable steps based on the discovered steps event
      #
      # @param event [Hash] The viable steps discovered event data
      def execute_viable_steps(event)
        task_id = event[:task_id]
        step_ids = event[:step_ids]
        processing_mode = event[:processing_mode] || 'sequential'

        Rails.logger.debug do
          "StepExecutor: Executing #{step_ids.size} steps for task #{task_id} in #{processing_mode} mode"
        end

        # Load the steps to execute
        steps = Tasker::WorkflowStep.where(workflow_step_id: step_ids)

        publish(Tasker::Constants::WorkflowEvents::STEPS_EXECUTION_STARTED, {
                  task_id: task_id,
                  step_ids: step_ids,
                  processing_mode: processing_mode,
                  started_at: Time.current
                })

        # Also publish to main LifecycleEvents bus
        Tasker::LifecycleEvents.fire(
          Tasker::Constants::WorkflowEvents::STEPS_EXECUTION_STARTED,
          {
            task_id: task_id,
            step_ids: step_ids,
            processing_mode: processing_mode,
            started_at: Time.current
          }
        )

        case processing_mode
        when 'concurrent'
          execute_steps_concurrently(steps)
        when 'sequential'
          execute_steps_sequentially(steps)
        else
          execute_steps_sequentially(steps) # Default to sequential
        end

        publish(Tasker::Constants::WorkflowEvents::STEPS_EXECUTION_COMPLETED, {
                  task_id: task_id,
                  step_ids: step_ids,
                  processing_mode: processing_mode,
                  completed_at: Time.current
                })

        # Also publish to main LifecycleEvents bus
        Tasker::LifecycleEvents.fire(
          Tasker::Constants::WorkflowEvents::STEPS_EXECUTION_COMPLETED,
          {
            task_id: task_id,
            step_ids: step_ids,
            processing_mode: processing_mode,
            completed_at: Time.current
          }
        )
      rescue StandardError => e
        Rails.logger.error { "StepExecutor: Error executing steps for task #{task_id}: #{e.message}" }

        publish(Tasker::Constants::WorkflowEvents::STEP_EXECUTION_FAILED, {
                  task_id: task_id,
                  step_ids: step_ids,
                  error: e.message,
                  failed_at: Time.current
                })

        # Also publish to main LifecycleEvents bus
        Tasker::LifecycleEvents.fire(
          Tasker::Constants::WorkflowEvents::STEP_EXECUTION_FAILED,
          {
            task_id: task_id,
            step_ids: step_ids,
            error: e.message,
            failed_at: Time.current
          }
        )

        raise
      end

      private

      # Execute steps concurrently using futures
      #
      # @param steps [Array<Tasker::WorkflowStep>] The steps to execute
      def execute_steps_concurrently(steps)
        Rails.logger.debug { "StepExecutor: Executing #{steps.size} steps concurrently" }

        processed_steps = []

        # Create futures for each step
        futures = steps.map do |step|
          Concurrent::Future.execute do
            execute_single_step(step)
            step # Return the step so we can track what was processed
          end
        end

        # Wait for all futures to complete with timeout
        futures.each do |future|
          begin
            # 30 second timeout per step to prevent indefinite hanging
            result = future.value(30)
            processed_steps << result if result
          rescue StandardError => e
            Rails.logger.error("StepExecutor: Error in concurrent step execution: #{e.message}")
            # Continue with other steps even if one fails
          end
        end

        # Update annotations for this batch of processed steps
        if processed_steps.any?
          first_step = processed_steps.first
          task = first_step.task
          task_handler = get_task_handler(task)
          sequence = get_sequence(task)
          task_handler.update_annotations(task, sequence, processed_steps)
        end
      end

      # Execute steps sequentially
      #
      # @param steps [Array<Tasker::WorkflowStep>] The steps to execute
      def execute_steps_sequentially(steps)
        Rails.logger.debug { "StepExecutor: Executing #{steps.size} steps sequentially" }

        processed_steps = []
        steps.each do |step|
          begin
            execute_single_step(step)
            processed_steps << step
          rescue StandardError => e
            Rails.logger.error("StepExecutor: Failed to execute step #{step.workflow_step_id}: #{e.message}")
            # Continue with other steps even if one fails
          end
        end

        # Update annotations for this batch of processed steps
        if processed_steps.any?
          first_step = processed_steps.first
          task = first_step.task
          task_handler = get_task_handler(task)
          sequence = get_sequence(task)
          task_handler.update_annotations(task, sequence, processed_steps)
        end
      end

      # Execute a single step by transitioning it to in_progress and calling the step handler
      #
      # This follows the exact pattern from TaskHandler::InstanceMethods#handle_one_step
      # but integrates with the event-driven orchestration system.
      #
      # @param step [Tasker::WorkflowStep] The step to execute
      def execute_single_step(step)
        Rails.logger.debug { "StepExecutor: Executing step #{step.workflow_step_id} (#{step.name})" }

        # Mark the step as in_process to prevent duplicate execution
        step.update_column(:in_process, true)

        # Load the task and get the task handler
        task = step.task
        task_handler = get_task_handler(task)
        sequence = get_sequence(task)

        # Build span context for telemetry
        span_context = build_step_span_context(task, step)

        # Use the lifecycle events to handle a step with proper span management
        # This will create a span that's properly connected to the parent task span
        Tasker::LifecycleEvents.fire_with_span(
          Tasker::Constants::ObservabilityEvents::Step::HANDLE,
          span_context.merge(attempt: step.attempts.to_i + 1)
        ) do
          # Get the step handler from the task handler
          handler = task_handler.get_step_handler(step)
          step.attempts ||= 0

          begin
            # Transition step to IN_PROGRESS before execution
            # Use the concern's safe_transition_to method
            safe_transition_to(step, Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS)

            # Now execute the step handler - this is the core missing piece!
            handler.handle(task, sequence, step)

            # Handle successful step completion
            handle_step_success(step, span_context)
          rescue StandardError => e
            # Handle step execution error
            handle_step_error(step, e, span_context)
          end

          # Common post-handling logic
          step.attempts += 1
          step.last_attempted_at = Time.zone.now

          # Check for retry or max retries reached
          handle_retry_events(step, span_context) if step.status == Tasker::Constants::WorkflowStepStatuses::ERROR

          step.save!
        end
      rescue StandardError => e
        Rails.logger.error { "StepExecutor: Failed to execute step #{step.workflow_step_id}: #{e.message}" }

        # Reset in_process flag on failure
        step.update_column(:in_process, false)

        # Use the concern's safe_transition_to method for error transition
        safe_transition_to(step, Tasker::Constants::WorkflowStepStatuses::ERROR)

        raise
      end

      # Get the task handler for a given task
      #
      # @param task [Tasker::Task] The task to get the handler for
      # @return [Object] The task handler instance
      # @raise [Tasker::ProceduralError] If no handler is registered for the task
      def get_task_handler(task)
        factory = Tasker::HandlerFactory.instance

        begin
          factory.get(task.name)
        rescue StandardError => e
          # If no handler is registered for this task, that's an error condition
          raise Tasker::ProceduralError, "No task handler for #{task.name}: #{e.message}"
        end
      end

      # Get the step sequence for a task
      #
      # @param task [Tasker::Task] The task to get the sequence for
      # @return [Tasker::Types::StepSequence] The sequence of workflow steps
      def get_sequence(task)
        # Load the task handler to use its step templates
        task_handler = get_task_handler(task)
        steps = Tasker::WorkflowStep.get_steps_for_task(task, task_handler.step_templates)
        task_handler.establish_step_dependencies_and_defaults(task, steps)
        Tasker::Types::StepSequence.new(steps: steps)
      end

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
      # This follows the exact pattern from TaskHandler::InstanceMethods#handle_step_success
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
      # This follows the exact pattern from TaskHandler::InstanceMethods#handle_step_error
      #
      # @param step [Tasker::WorkflowStep] The step that encountered an error
      # @param error [StandardError] The error that occurred
      # @param span_context [Hash] The span context data
      # @return [void]
      def handle_step_error(step, error, span_context)
        # Use state machine to transition step to error
        step.state_machine.transition_to!(Tasker::Constants::WorkflowStepStatuses::ERROR)

        # Store error details in step results
        step.results ||= {}
        step.results = step.results.merge(
          error: error.message,
          backtrace: error.backtrace&.join("\n")
        )

        # Use EventPayloadBuilder for standardized payload
        payload = Tasker::Events::EventPayloadBuilder.build_step_payload(
          step,
          event_type: :failed,
          additional_context: span_context.merge(
            error: error.message,
            exception_class: error.class.name
          )
        )

        Tasker::LifecycleEvents.fire(
          Tasker::Constants::StepEvents::FAILED,
          payload
        )
      end

      # Handle retry events for steps in error state
      #
      # This follows the pattern from TaskHandler::InstanceMethods#handle_retry_events
      #
      # @param step [Tasker::WorkflowStep] The step to handle retries for
      # @param span_context [Hash] The span context data
      # @return [void]
      def handle_retry_events(step, span_context)
        if step.attempts >= step.retry_limit
          # Max retries reached
          Tasker::LifecycleEvents.fire(
            Tasker::Constants::StepEvents::MAX_RETRIES_REACHED,
            span_context.merge(
              step_id: step.workflow_step_id,
              step_name: step.name,
              attempts: step.attempts,
              retry_limit: step.retry_limit
            )
          )
        end
        # Note: Retry scheduling would be handled by a separate RetryScheduler component
        # For now, we just fire the max retries event
      end
    end
  end
end
