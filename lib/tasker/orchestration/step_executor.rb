# frozen_string_literal: true

require 'concurrent'
require_relative '../concerns/idempotent_state_transitions'
require_relative '../concerns/event_publisher'
require_relative '../types/step_sequence'

module Tasker
  module Orchestration
    # StepExecutor handles the execution of workflow steps with concurrent processing
    #
    # This class provides the implementation for step execution while preserving
    # the original concurrent processing capabilities using concurrent-ruby.
    # It fires lifecycle events for observability.
    class StepExecutor
      include Tasker::Concerns::IdempotentStateTransitions
      include Tasker::Concerns::EventPublisher

      # ⚠️  PRIORITY 0 FIX: Limit concurrency to prevent database connection exhaustion
      MAX_CONCURRENT_STEPS = 3

      # Execute a collection of viable steps
      #
      # This method preserves the original concurrent processing logic while
      # adding observability through lifecycle events.
      #
      # @param task [Tasker::Task] The task containing the steps
      # @param sequence [Tasker::Types::StepSequence] The step sequence
      # @param viable_steps [Array<Tasker::WorkflowStep>] Steps ready for execution
      # @param task_handler [Object] The task handler instance
      # @return [Array<Tasker::WorkflowStep>] Successfully processed steps
      def execute_steps(task, sequence, viable_steps, task_handler)
        return [] if viable_steps.empty?

        # Determine processing mode
        processing_mode = determine_processing_mode(task_handler)

        # Fire observability event through orchestrator
        publish_event(
          Tasker::Constants::WorkflowEvents::STEPS_EXECUTION_STARTED,
          {
            task_id: task.task_id,
            step_count: viable_steps.size,
            processing_mode: processing_mode
          }
        )

        # PRESERVE: Original concurrent processing logic
        processed_steps = if processing_mode == 'concurrent'
                            execute_steps_concurrently(task, sequence, viable_steps, task_handler)
                          else
                            execute_steps_sequentially(task, sequence, viable_steps, task_handler)
                          end

        # Fire completion event through orchestrator
        publish_event(
          Tasker::Constants::WorkflowEvents::STEPS_EXECUTION_COMPLETED,
          {
            task_id: task.task_id,
            processed_count: processed_steps.size,
            successful_count: processed_steps.count do |s|
              s&.status == Tasker::Constants::WorkflowStepStatuses::COMPLETE
            end
          }
        )

        processed_steps.compact
      end

      # Handle viable steps discovered event
      #
      # Convenience method for event-driven workflows that takes an event payload
      # and executes the discovered steps.
      #
      # @param event [Hash] Event payload with task_id, step_ids, and processing_mode
      def handle_viable_steps_discovered(event)
        task_id = event[:task_id]
        step_ids = event[:step_ids] || []

        return [] if step_ids.empty?

        task = Tasker::Task.find(task_id)
        task_handler = Tasker::HandlerFactory.instance.get(task.name)
        sequence = Tasker::Orchestration::StepSequenceFactory.get_sequence(task, task_handler)
        viable_steps = task.workflow_steps.where(workflow_step_id: step_ids)

        execute_steps(task, sequence, viable_steps, task_handler)
      end

      # Execute a single step with state machine transitions and error handling
      #
      # @param task [Tasker::Task] The task containing the step
      # @param sequence [Tasker::Types::StepSequence] The step sequence
      # @param step [Tasker::WorkflowStep] The step to execute
      # @param task_handler [Object] The task handler instance
      # @return [Tasker::WorkflowStep, nil] The executed step or nil if failed
      def execute_single_step(task, sequence, step, task_handler)
        # Guard clauses - fail fast if preconditions aren't met
        return nil unless validate_step_preconditions(step)
        return nil unless ensure_step_has_initial_state(step)
        return nil unless step_ready_for_execution?(step)

        # Main execution workflow
        execute_step_workflow(task, sequence, step, task_handler)
      rescue StandardError => e
        # Log unexpected errors that occur outside the normal workflow
        Rails.logger.error("StepExecutor: Unexpected error in execute_single_step for step #{step&.workflow_step_id}: #{e.message}")
        nil
      end

      private

      # Validate that the step and database connection are ready
      def validate_step_preconditions(step)
        unless ActiveRecord::Base.connection.active?
          Rails.logger.error("StepExecutor: Database connection inactive for step #{step&.workflow_step_id}")
          return false
        end

        step = step.reload if step&.persisted?
        unless step
          Rails.logger.error('StepExecutor: Step is nil or not persisted')
          return false
        end

        true
      rescue ActiveRecord::ConnectionNotEstablished, PG::ConnectionBad => e
        Rails.logger.error("StepExecutor: Database connection error for step #{step&.workflow_step_id}: #{e.message}")
        false
      rescue StandardError => e
        Rails.logger.error("StepExecutor: Unexpected error checking step #{step&.workflow_step_id}: #{e.message}")
        false
      end

      # Ensure step has an initial state, set to pending if blank
      def ensure_step_has_initial_state(step)
        current_state = step.state_machine.current_state
        return true if current_state.present?

        Rails.logger.debug { "StepExecutor: Step #{step.workflow_step_id} has no state, setting to pending" }
        unless safe_transition_to(step, Tasker::Constants::WorkflowStepStatuses::PENDING)
          Rails.logger.error("StepExecutor: Failed to initialize step #{step.workflow_step_id} to pending state")
          return false
        end

        step.reload
        true
      end

      # Check if step is in the correct state for execution
      def step_ready_for_execution?(step)
        current_state = step.state_machine.current_state
        return true if current_state == Tasker::Constants::WorkflowStepStatuses::PENDING

        Rails.logger.debug do
          "StepExecutor: Skipping step #{step.workflow_step_id} - not pending (current: '#{current_state}')"
        end
        false
      end

      # Execute the main step workflow: transition -> execute -> complete
      def execute_step_workflow(task, sequence, step, task_handler)
        publish_execution_started_event(task, step)

        # Execute step handler and handle both success and error cases
        begin
          # Transition to in_progress first - if this fails, it should be treated as an error
          transition_step_to_in_progress!(step)

          execute_step_handler(task, sequence, step, task_handler)
          complete_step_execution(task, step)
        rescue StandardError => e
          # Store error data in step.results like legacy code
          store_step_error_data(step, e)

          # Complete error step execution with persistence (similar to complete_step_execution but for errors)
          complete_error_step_execution(task, step)
          nil
        end
      end

      # Publish event for step execution start
      def publish_execution_started_event(_task, step)
        # Use clean API for step execution start
        publish_step_started(step)
      end

      # Transition step to in_progress state (bang version that raises on failure)
      def transition_step_to_in_progress!(step)
        unless safe_transition_to(step, Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS)
          current_state = step.state_machine.current_state
          error_message = "Cannot transition step #{step.workflow_step_id} from '#{current_state}' to 'in_progress'. " \
                          'Check step dependencies and current state.'

          Rails.logger.warn("StepExecutor: #{error_message}")
          raise Tasker::ProceduralError, error_message
        end

        true
      end

      # Execute the actual step handler logic
      def execute_step_handler(task, sequence, step, task_handler)
        step_handler = task_handler.get_step_handler(step)
        step_handler.handle(task, sequence, step)
      end

      # Complete step execution and publish completion event
      #
      # This method ensures atomic completion by wrapping both the step save
      # and state transition in a database transaction. This is critical for
      # idempotency: if either operation fails, the step remains in "in_progress"
      # and can be safely retried without repeating the actual work.
      def complete_step_execution(task, step)
        completed_step = nil

        # Update attempt tracking like legacy code (for consistency with error path)
        step.attempts ||= 0
        step.attempts += 1
        step.last_attempted_at = Time.zone.now

        # Use database transaction to ensure atomic completion
        ActiveRecord::Base.transaction do
          # STEP 1: Save the step results first
          # This persists the output of the work that has already been performed
          step.save!

          # STEP 2: Transition to complete state
          # This marks the step as done, but only if the save succeeded
          unless safe_transition_to(step, Tasker::Constants::WorkflowStepStatuses::COMPLETE)
            Rails.logger.error("StepExecutor: Failed to transition step #{step.workflow_step_id} to complete")
            # Raise exception to trigger transaction rollback
            raise ActiveRecord::Rollback, "Failed to transition step #{step.workflow_step_id} to complete state"
          end

          completed_step = step
        end

        # If we got here, both save and transition succeeded
        unless completed_step
          Rails.logger.error("StepExecutor: Step completion transaction rolled back for step #{step.workflow_step_id}")
          return nil
        end

        # Publish completion event outside transaction (for performance)
        publish_event(
          Tasker::Constants::StepEvents::COMPLETED,
          {
            task_id: task.task_id,
            step_id: step.workflow_step_id,
            step_name: step.name,
            attempt_number: step.attempts,
            execution_duration: step.processed_at&.-(step.updated_at)
          }
        )

        Rails.logger.debug { "StepExecutor: Successfully completed step #{step.workflow_step_id}" }
        completed_step
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => e
        Rails.logger.error("StepExecutor: Failed to save step #{step.workflow_step_id}: #{e.message}")
        nil
      rescue StandardError => e
        Rails.logger.error("StepExecutor: Unexpected error completing step #{step.workflow_step_id}: #{e.message}")
        nil
      end

      # Store error data in step results (matching legacy pattern)
      def store_step_error_data(step, error)
        step.results ||= {}
        step.results = step.results.merge(
          error: error.to_s,
          backtrace: error.backtrace.join("\n"),
          error_class: error.class.name
        )

        # Update attempt tracking like legacy code
        step.attempts ||= 0
        step.attempts += 1
        step.last_attempted_at = Time.zone.now
      end

      # Complete error step execution with persistence and state transition
      #
      # This mirrors complete_step_execution but handles error state persistence.
      # Critical: We MUST save error steps to preserve error data and attempt tracking.
      def complete_error_step_execution(task, step)
        completed_error_step = nil

        # Use database transaction to ensure atomic error completion
        ActiveRecord::Base.transaction do
          # STEP 1: Save the step with error data first
          # This persists the error information and attempt tracking
          step.save!

          # STEP 2: Transition to error state
          # This marks the step as failed, but only if the save succeeded
          unless safe_transition_to(step, Tasker::Constants::WorkflowStepStatuses::ERROR)
            Rails.logger.error("StepExecutor: Failed to transition step #{step.workflow_step_id} to error")
            # Raise exception to trigger transaction rollback
            raise ActiveRecord::Rollback, "Failed to transition step #{step.workflow_step_id} to error state"
          end

          completed_error_step = step
        end

        # If we got here, both save and transition succeeded
        unless completed_error_step
          Rails.logger.error("StepExecutor: Error step completion transaction rolled back for step #{step.workflow_step_id}")
          return nil
        end

        # Publish error event outside transaction (for performance)
        publish_event(
          Tasker::Constants::StepEvents::FAILED,
          {
            task_id: task.task_id,
            step_id: step.workflow_step_id,
            step_name: step.name,
            error_message: step.results['error'],
            error_class: step.results['error_class'],
            attempt_number: step.attempts,
            backtrace: step.results['backtrace']&.split("\n")&.first(10)
          }
        )

        Rails.logger.debug { "StepExecutor: Successfully saved error step #{step.workflow_step_id}" }
        completed_error_step
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => e
        Rails.logger.error("StepExecutor: Failed to save error step #{step.workflow_step_id}: #{e.message}")
        nil
      rescue StandardError => e
        Rails.logger.error("StepExecutor: Unexpected error completing error step #{step.workflow_step_id}: #{e.message}")
        nil
      end

      # Execute steps concurrently using concurrent-ruby
      #
      # @param task [Tasker::Task] The task containing the steps
      # @param sequence [Tasker::Types::StepSequence] The step sequence
      # @param viable_steps [Array<Tasker::WorkflowStep>] Steps to execute
      # @param task_handler [Object] The task handler instance
      # @return [Array<Tasker::WorkflowStep>] Processed steps
      def execute_steps_concurrently(task, sequence, viable_steps, task_handler)
        # ⚠️  PRIORITY 0 FIX: Process in smaller batches to prevent database connection exhaustion
        results = []

        viable_steps.each_slice(MAX_CONCURRENT_STEPS) do |step_batch|
          # Use concurrent-ruby for parallel execution within batch
          futures = step_batch.map do |step|
            Concurrent::Future.execute do
              # Ensure each future has its own database connection
              ActiveRecord::Base.connection_pool.with_connection do
                execute_single_step(task, sequence, step, task_handler)
              end
            end
          end

          # Wait for batch to complete and collect results
          begin
            batch_results = futures.map(&:value)
            results.concat(batch_results.compact)
          ensure
            # ⚠️  MEMORY FIX: Explicitly clear future references to prevent memory leaks
            futures.clear
          end
        end

        results
      end

      # Execute steps sequentially
      #
      # @param task [Tasker::Task] The task containing the steps
      # @param sequence [Tasker::Types::StepSequence] The step sequence
      # @param viable_steps [Array<Tasker::WorkflowStep>] Steps to execute
      # @param task_handler [Object] The task handler instance
      # @return [Array<Tasker::WorkflowStep>] Processed steps
      def execute_steps_sequentially(task, sequence, viable_steps, task_handler)
        viable_steps.map do |step|
          execute_single_step(task, sequence, step, task_handler)
        end
      end

      # Determine processing mode based on task handler configuration
      #
      # @param task_handler [Object] The task handler instance
      # @return [String] Processing mode ('concurrent' or 'sequential')
      def determine_processing_mode(task_handler)
        if task_handler.respond_to?(:use_concurrent_processing?) &&
           task_handler.use_concurrent_processing?
          'concurrent'
        else
          'sequential'
        end
      end
    end
  end
end
