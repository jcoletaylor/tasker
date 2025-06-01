# frozen_string_literal: true

require 'concurrent'
require_relative '../concerns/idempotent_state_transitions'
require_relative '../concerns/lifecycle_event_helpers'
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
      include Tasker::Concerns::LifecycleEventHelpers
      include Tasker::Concerns::EventPublisher

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
        # Ensure step has a proper state before processing
        current_state = step.state_machine.current_state

        # Handle case where step doesn't have initial state
        if current_state.blank?
          Rails.logger.debug { "StepExecutor: Step #{step.workflow_step_id} has no state, setting to pending" }
          unless safe_transition_to(step, Tasker::Constants::WorkflowStepStatuses::PENDING)
            Rails.logger.error("StepExecutor: Failed to initialize step #{step.workflow_step_id} to pending state")
            return nil
          end
          # Reload to get updated state after transition
          step.reload
          current_state = step.state_machine.current_state
        end

        # Only process pending steps
        unless current_state == Tasker::Constants::WorkflowStepStatuses::PENDING
          Rails.logger.debug do
            "StepExecutor: Skipping step #{step.workflow_step_id} - not pending (current: '#{current_state}')"
          end
          return nil
        end

        begin
          # Fire step execution started event through orchestrator
          publish_event(
            Tasker::Constants::StepEvents::EXECUTION_REQUESTED,
            {
              task_id: task.task_id,
              step_id: step.workflow_step_id,
              step_name: step.name
            }
          )

          # Transition to in_progress using state machine
          unless safe_transition_to(step, Tasker::Constants::WorkflowStepStatuses::IN_PROGRESS)
            current_state = step.state_machine.current_state
            Rails.logger.warn do
              "StepExecutor: Cannot start step #{step.workflow_step_id} - transition from '#{current_state}' " \
              "to 'in_progress' blocked. This may be due to: " \
              "1) Step not in pending state, 2) Dependencies not met, or 3) Guard clause restrictions. " \
              "Check step dependencies and current state."
            end
            return nil
          end

          # Get the step handler and execute it
          step_handler = task_handler.get_step_handler(step)
          step_handler.handle(task, sequence, step)

          # Transition to complete
          if safe_transition_to(step, Tasker::Constants::WorkflowStepStatuses::COMPLETE)
            # Fire completion event through orchestrator
            publish_event(
              Tasker::Constants::StepEvents::COMPLETED,
              {
                task_id: task.task_id,
                step_id: step.workflow_step_id,
                step_name: step.name,
                execution_duration: step.processed_at&.-(step.updated_at)
              }
            )

            Rails.logger.debug { "StepExecutor: Successfully completed step #{step.workflow_step_id}" }
            step
          else
            Rails.logger.error("StepExecutor: Failed to transition step #{step.workflow_step_id} to complete")
            nil
          end
        rescue StandardError => e
          Rails.logger.error("StepExecutor: Error executing step #{step.workflow_step_id}: #{e.message}")

          # Transition to error state
          safe_transition_to(step, Tasker::Constants::WorkflowStepStatuses::ERROR)

          # Fire error event through orchestrator
          publish_event(
            Tasker::Constants::StepEvents::FAILED,
            {
              task_id: task.task_id,
              step_id: step.workflow_step_id,
              step_name: step.name,
              error_message: e.message,
              error_class: e.class.name,
              backtrace: e.backtrace&.first(10)
            }
          )

          nil
        end
      end

      private

      # Execute steps concurrently using concurrent-ruby
      #
      # @param task [Tasker::Task] The task containing the steps
      # @param sequence [Tasker::Types::StepSequence] The step sequence
      # @param viable_steps [Array<Tasker::WorkflowStep>] Steps to execute
      # @param task_handler [Object] The task handler instance
      # @return [Array<Tasker::WorkflowStep>] Processed steps
      def execute_steps_concurrently(task, sequence, viable_steps, task_handler)
        # Use concurrent-ruby for parallel execution
        futures = viable_steps.map do |step|
          Concurrent::Future.execute do
            execute_single_step(task, sequence, step, task_handler)
          end
        end

        # Wait for all futures to complete and collect results
        futures.map(&:value)
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
