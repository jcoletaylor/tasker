# frozen_string_literal: true

module TestOrchestration
  # TestReenqueuer provides a test-specific reenqueuer strategy that manages
  # retry queues instead of using ActiveJob for synchronous testing
  #
  # This strategy allows tests to control the retry loop and process tasks
  # synchronously while respecting the orchestration system's retry logic.
  class TestReenqueuer
    class << self
      attr_accessor :retry_queue, :active

      # Activate test reenqueuer mode
      def activate!
        self.active = true
        self.retry_queue = []
      end

      # Deactivate test reenqueuer mode
      def deactivate!
        self.active = false
        self.retry_queue = []
      end

      # Check if test reenqueuer is active
      def active?
        !!@active
      end

      # Get tasks from retry queue
      def pending_retries
        retry_queue.dup
      end

      # Clear retry queue
      def clear_retry_queue!
        self.retry_queue = []
      end

      # Get retry queue size
      delegate :size, to: :retry_queue, prefix: true
    end

    # Re-enqueue a task for continued processing (test mode)
    #
    # Instead of enqueueing to ActiveJob, adds task to retry queue
    # for synchronous processing by test coordinator
    #
    # @param task [Tasker::Task] The task to re-enqueue
    # @param reason [String] The reason for re-enqueueing
    # @return [Boolean] True if re-enqueueing was successful
    def reenqueue_task(task, reason: 'test_retry')
      return false unless self.class.active?

      # Add to retry queue instead of ActiveJob
      self.class.retry_queue << {
        task: task,
        reason: reason,
        enqueued_at: Time.current
      }

      Rails.logger.debug { "TestReenqueuer: Task #{task.task_id} added to retry queue (reason: #{reason})" }
      true
    rescue StandardError => e
      Rails.logger.error("TestReenqueuer: Failed to add task #{task.task_id} to retry queue: #{e.message}")
      false
    end

    # Schedule a delayed re-enqueue (test mode)
    #
    # In test mode, we ignore delays and add immediately to retry queue
    #
    # @param task [Tasker::Task] The task to re-enqueue
    # @param delay_seconds [Integer] Number of seconds to delay (ignored in test mode)
    # @param reason [String] The reason for delayed re-enqueueing
    # @return [Boolean] True if scheduling was successful
    def reenqueue_task_delayed(task, delay_seconds:, reason: 'test_delayed_retry')
      return false unless self.class.active?

      # In test mode, ignore delay and add immediately
      self.class.retry_queue << {
        task: task,
        reason: reason,
        delay_seconds: delay_seconds,
        enqueued_at: Time.current
      }

      Rails.logger.debug do
        "TestReenqueuer: Task #{task.task_id} added to retry queue with #{delay_seconds}s delay (ignored in test)"
      end
      true
    rescue StandardError => e
      Rails.logger.error("TestReenqueuer: Failed to schedule delayed retry for task #{task.task_id}: #{e.message}")
      false
    end
  end
end
