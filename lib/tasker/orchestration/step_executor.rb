# frozen_string_literal: true

require 'concurrent'
require_relative '../concerns/idempotent_state_transitions'
require_relative '../concerns/lifecycle_event_helpers'
require_relative '../concerns/orchestration_publisher'

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
      include Tasker::Concerns::OrchestrationPublisher

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
            successful_count: processed_steps.count { |s| s&.status == Tasker::Constants::WorkflowStepStatuses::COMPLETE }
          }
        )

        processed_steps.compact
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

      # Execute a single step with state machine transitions and error handling
      #
      # @param task [Tasker::Task] The task containing the step
      # @param sequence [Tasker::Types::StepSequence] The step sequence
      # @param step [Tasker::WorkflowStep] The step to execute
      # @param task_handler [Object] The task handler instance
      # @return [Tasker::WorkflowStep, nil] The executed step or nil if failed
      def execute_single_step(task, sequence, step, task_handler)
        # Only process pending steps
        unless step.state_machine.current_state == Tasker::Constants::WorkflowStepStatuses::PENDING
          Rails.logger.debug("StepExecutor: Skipping step #{step.workflow_step_id} - not pending (#{step.state_machine.current_state})")
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
            Rails.logger.warn("StepExecutor: Failed to transition step #{step.workflow_step_id} to in_progress")
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

            Rails.logger.debug("StepExecutor: Successfully completed step #{step.workflow_step_id}")
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
