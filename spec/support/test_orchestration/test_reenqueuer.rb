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

      # Process all queued tasks synchronously
      def process_queue!
        return if retry_queue.empty?

        queued_tasks = retry_queue.dup
        self.retry_queue = []

        queued_tasks.each do |entry|
          task = entry[:task]
          reason = entry[:reason]

          Rails.logger.debug { "TestReenqueuer: Processing queued task #{task.task_id} (reason: #{reason})" }

          # Simulate what TaskRunnerJob would do - call the task handler
          handler_name = extract_base_handler_name(task.name)
          handler = Tasker::HandlerFactory.instance.get(handler_name)

          if handler
            handler.handle(task)
          else
            Rails.logger.error("TestReenqueuer: No handler found for task #{task.task_id} (handler: #{handler_name})")
          end
        end
      end

      # Check if there are tasks to process
      def has_queued_tasks?
        retry_queue.any?
      end

      private

      # Extract base handler name from task name (remove unique suffix)
      def extract_base_handler_name(task_name)
        # Remove the unique suffix pattern: _timestamp_randomnumber
        # e.g., "linear_workflow_task_1749555645_529" -> "linear_workflow_task"
        task_name.gsub(/_\d+_\d+$/, '')
      end
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

      # TESTING OPTIMIZATION: Clear backoff timing to make failed steps immediately ready
      # In tests, we want to test retry logic without waiting for backoff periods
      clear_backoff_timing_for_task(task)

      # Add to retry queue instead of ActiveJob
      self.class.retry_queue << {
        task: task,
        reason: reason,
        enqueued_at: Time.current
      }

      Rails.logger.debug { "TestReenqueuer: Task #{task.task_id} added to retry queue (reason: #{reason})" }

      # Don't auto-process here - let TestCoordinator handle the queue processing loop
      # This prevents infinite recursion where reenqueue -> process_queue -> handle -> reenqueue

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

      # TESTING OPTIMIZATION: Clear backoff timing to make failed steps immediately ready
      clear_backoff_timing_for_task(task)

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

      # Don't auto-process here - let TestCoordinator handle the queue processing loop
      # This prevents infinite recursion where reenqueue -> process_queue -> handle -> reenqueue

      true
    rescue StandardError => e
      Rails.logger.error("TestReenqueuer: Failed to schedule delayed retry for task #{task.task_id}: #{e.message}")
      false
    end

    private

    # Clear backoff timing for a task to make failed steps immediately ready for retry
    #
    # This is a testing optimization that bypasses exponential backoff logic
    # by backdating the failure timestamps, making steps immediately eligible for retry
    #
    # @param task [Tasker::Task] The task to clear backoff timing for
    def clear_backoff_timing_for_task(task)
      # Find all error transitions for this task that happened recently
      task.workflow_steps.joins(:workflow_step_transitions)
          .where(tasker_workflow_step_transitions: { to_state: 'error', most_recent: true })
          .find_each do |step|
            # Backdate the error transition to bypass exponential backoff
            error_transition = step.workflow_step_transitions.where(to_state: 'error', most_recent: true).first

            if error_transition
              # Set the failure time to 1 minute ago to ensure backoff has elapsed
              backdated_time = 1.minute.ago
              error_transition.update!(created_at: backdated_time, updated_at: backdated_time)

              Rails.logger.debug do
                "TestReenqueuer: Backdated error transition for step #{step.workflow_step_id} to #{backdated_time}"
              end
            end

            # Also clear any explicit backoff timing
            step.update!(last_attempted_at: 1.minute.ago) if step.last_attempted_at.present?

            # Clear any explicit backoff request
            step.update!(backoff_request_seconds: nil) if step.backoff_request_seconds.present?
          end
    rescue StandardError => e
      Rails.logger.warn("TestReenqueuer: Failed to clear backoff timing for task #{task.task_id}: #{e.message}")
    end
  end
end
