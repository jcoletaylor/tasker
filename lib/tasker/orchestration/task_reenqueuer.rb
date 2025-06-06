# frozen_string_literal: true

require_relative '../concerns/idempotent_state_transitions'
require_relative '../concerns/event_publisher'

module Tasker
  module Orchestration
    # TaskReenqueuer handles the mechanics of re-enqueueing tasks for continued processing
    #
    # This class provides implementation for task re-enqueueing logic while firing
    # lifecycle events for observability. Separates the decision to re-enqueue
    # from the mechanics of how re-enqueueing works.
    class TaskReenqueuer
      include Tasker::Concerns::IdempotentStateTransitions
      include Tasker::Concerns::EventPublisher

      # Re-enqueue a task for continued processing
      #
      # @param task [Tasker::Task] The task to re-enqueue
      # @param reason [String] The reason for re-enqueueing (for observability)
      # @return [Boolean] True if re-enqueueing was successful
      def reenqueue_task(task, reason: Constants::TaskFinalization::ReenqueueReasons::PENDING_STEPS_REMAINING)
        # Fire re-enqueue started event
        publish_task_reenqueue_started(task, reason: reason)

        # Transition task back to pending state for clarity
        if safe_transition_to(task, Tasker::Constants::TaskStatuses::PENDING)
          Rails.logger.debug { "TaskReenqueuer: Task #{task.task_id} transitioned back to pending" }
        end

        # Enqueue the task for processing
        Tasker::TaskRunnerJob.perform_later(task.task_id)

        # Fire re-enqueue completed event
        publish_task_reenqueue_requested(task, reason: reason)

        Rails.logger.debug { "TaskReenqueuer: Task #{task.task_id} re-enqueued due to #{reason}" }
        true
      rescue StandardError => e
        # Fire re-enqueue failed event
        publish_task_reenqueue_failed(task, reason: reason, error: e.message)

        Rails.logger.error("TaskReenqueuer: Failed to re-enqueue task #{task.task_id}: #{e.message}")
        false
      end

      # Schedule a delayed re-enqueue (for retry scenarios)
      #
      # @param task [Tasker::Task] The task to re-enqueue
      # @param delay_seconds [Integer] Number of seconds to delay
      # @param reason [String] The reason for delayed re-enqueueing
      # @return [Boolean] True if scheduling was successful
      def reenqueue_task_delayed(task, delay_seconds:,
                                 reason: Constants::TaskFinalization::ReenqueueReasons::RETRY_BACKOFF)
        # Fire delayed re-enqueue started event
        publish_task_reenqueue_delayed(task, delay_seconds: delay_seconds, reason: reason)

        # Schedule the delayed job
        Tasker::TaskRunnerJob.set(wait: delay_seconds.seconds).perform_later(task.task_id)

        Rails.logger.debug do
          "TaskReenqueuer: Task #{task.task_id} scheduled for re-enqueue in #{delay_seconds} seconds"
        end
        true
      rescue StandardError => e
        Rails.logger.error("TaskReenqueuer: Failed to schedule delayed re-enqueue for task #{task.task_id}: #{e.message}")
        false
      end
    end
  end
end
