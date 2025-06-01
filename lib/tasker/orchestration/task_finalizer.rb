# frozen_string_literal: true

require_relative '../concerns/idempotent_state_transitions'
require_relative '../concerns/event_publisher'
require_relative '../task_handler/step_group'
require_relative 'task_reenqueuer'

module Tasker
  module Orchestration
    # TaskFinalizer handles task completion and finalization logic
    #
    # This class provides implementation for task finalization while firing
    # lifecycle events for observability. No complex event subscriptions needed.
    class TaskFinalizer
      include Tasker::Concerns::IdempotentStateTransitions
      include Tasker::Concerns::EventPublisher

      # Check if the task is blocked by errors
      #
      # @param task [Tasker::Task] The task to check
      # @param sequence [Tasker::Types::StepSequence] The step sequence
      # @param processed_steps [Array<Tasker::WorkflowStep>] Recently processed steps
      # @return [Boolean] True if task is blocked by errors
      def blocked_by_errors?(task, _sequence, _processed_steps)
        # Get steps that are in error state using the state machine scope
        error_steps = task.workflow_steps.failed

        if error_steps.exists?
          Rails.logger.debug { "TaskFinalizer: Task #{task.task_id} is blocked by #{error_steps.count} error steps" }

          # Log instead of firing unregistered event
          Rails.logger.info("TaskFinalizer: Task #{task.task_id} blocked by #{error_steps.count} error steps: #{error_steps.joins(:named_step).pluck('tasker_named_steps.name')}")

          true
        else
          false
        end
      end

      # Finalize a task with processed steps
      #
      # @param task [Tasker::Task] The task to finalize
      # @param sequence [Tasker::Types::StepSequence] The step sequence
      # @param processed_steps [Array<Tasker::WorkflowStep>] All processed steps
      def finalize_task_with_steps(task, _sequence, processed_steps)
        # Fire finalization started event through orchestrator
        publish_event(
          Tasker::Constants::WorkflowEvents::TASK_FINALIZATION_STARTED,
          {
            task_id: task.task_id,
            total_processed_steps: processed_steps.size
          }
        )

        # Use existing finalization logic
        finalize_task(task.task_id)

        # Fire finalization completed event through orchestrator
        publish_event(
          Tasker::Constants::WorkflowEvents::TASK_FINALIZATION_COMPLETED,
          {
            task_id: task.task_id,
            final_status: task.reload.status
          }
        )
      end

      # Finalize a task based on its current state
      #
      # @param task_id [Integer] The task ID to finalize
      def finalize_task(task_id)
        task = Tasker::Task.find(task_id)
        sequence = get_sequence_for_task(task)
        step_group = Tasker::TaskHandler::StepGroup.build(task, sequence, [])

        # Express framework-level decisions through focused method calls
        if step_group.complete?
          finalize_complete_task(task)
        elsif step_group.error?
          finalize_error_task(task, step_group)
        elsif step_group.pending?
          reenqueue_task(task)
        else
          handle_unclear_task_state(task, step_group)
        end
      end

      # Handle no viable steps event
      #
      # Convenience method for event-driven workflows when no viable steps are found.
      # This triggers task finalization to determine next action.
      #
      # @param event [Hash] Event payload with task_id
      def handle_no_viable_steps(event)
        task_id = event[:task_id] || event
        finalize_task(task_id)
      end

      private

      # Framework Decision: Mark task as successfully completed
      #
      # @param task [Tasker::Task] The task to complete
      def finalize_complete_task(task)
        return unless safe_transition_to(task, Tasker::Constants::TaskStatuses::COMPLETE)

        publish_event(
          Tasker::Constants::TaskEvents::COMPLETED,
          {
            task_id: task.task_id,
            completed_at: Time.current
          }
        )

        Rails.logger.info("TaskFinalizer: Task #{task.task_id} completed successfully")
      end

      # Framework Decision: Mark task as failed due to step errors
      #
      # @param task [Tasker::Task] The task to mark as failed
      # @param step_group [Tasker::TaskHandler::StepGroup] The step group with error information
      def finalize_error_task(task, step_group)
        return unless safe_transition_to(task, Tasker::Constants::TaskStatuses::ERROR)

        publish_event(
          Tasker::Constants::TaskEvents::FAILED,
          {
            task_id: task.task_id,
            reason: 'steps_in_error_state',
            error_details: step_group.debug_state
          }
        )

        Rails.logger.info("TaskFinalizer: Task #{task.task_id} failed due to step errors")
      end

      # Framework Decision: Re-enqueue task for continued processing
      #
      # @param task [Tasker::Task] The task to re-enqueue
      def reenqueue_task(task)
        # Delegate to specialized TaskReenqueuer class
        task_reenqueuer = Tasker::Orchestration::TaskReenqueuer.new
        task_reenqueuer.reenqueue_task(task, reason: 'pending_steps_remaining')
      end

      # Framework Decision: Handle unclear task state for investigation
      #
      # @param task [Tasker::Task] The task in unclear state
      # @param step_group [Tasker::TaskHandler::StepGroup] The step group for debugging
      def handle_unclear_task_state(task, step_group)
        debug_info = step_group.debug_state

        Rails.logger.warn(
          "TaskFinalizer: Task #{task.task_id} in unclear state - " \
          "complete: #{debug_info[:is_complete]}, " \
          "pending: #{debug_info[:is_pending]}, " \
          "has_errors: #{debug_info[:has_errors]}, " \
          "step_statuses: #{debug_info[:step_statuses]}"
        )

        # For unclear states, we could fire a special event for monitoring/alerting
        publish_event(
          Tasker::Constants::WorkflowEvents::TASK_STATE_UNCLEAR,
          {
            task_id: task.task_id,
            debug_state: debug_info
          }
        )
      end

      # Get sequence for a task
      #
      # @param task [Tasker::Task] The task
      # @return [Tasker::Types::StepSequence] The step sequence
      def get_sequence_for_task(task)
        # Get task handler and use it to get sequence
        handler_factory = Tasker::HandlerFactory.instance
        task_handler = handler_factory.get(task.name)
        Tasker::Orchestration::StepSequenceFactory.get_sequence(task, task_handler)
      end
    end
  end
end
