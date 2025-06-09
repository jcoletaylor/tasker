# frozen_string_literal: true

module Tasker
  module Orchestration
    # TestCoordinator provides test-specific orchestration bypassing ActiveJob
    #
    # This coordinator is designed specifically for testing scenarios where we need:
    # - Synchronous execution without job queues
    # - Configurable failure patterns for testing retry logic
    # - Idempotency testing through re-execution
    # - Performance testing with large datasets
    #
    # Usage:
    #   # In test environment, override the default orchestration
    #   Tasker::Orchestration::TestCoordinator.activate!
    #
    #   # Create and process tasks synchronously
    #   task = create(:complex_workflow, :diamond_workflow)
    #   TestCoordinator.process_task_synchronously(task)
    #
    class TestCoordinator
      include Tasker::Concerns::EventPublisher

      class << self
        attr_accessor :active, :execution_log, :failure_patterns, :retry_tracking

        # Activate test coordination mode
        def activate!
          self.active = true
          self.execution_log = []
          self.failure_patterns = {}
          self.retry_tracking = {}

          # Override TaskRunnerJob to use synchronous processing
          patch_task_runner_job!
        end

        # Deactivate test coordination (restore normal behavior)
        def deactivate!
          self.active = false
          restore_task_runner_job!
        end

        # Check if test coordination is active
        def active?
          !!@active
        end

        # Configure failure patterns for specific steps
        #
        # @param step_name [String] The step name to configure
        # @param failure_count [Integer] Number of times to fail before succeeding
        # @param failure_message [String] Custom failure message
        def configure_step_failure(step_name, failure_count: 2, failure_message: 'Test failure')
          failure_patterns[step_name] = {
            failure_count: failure_count,
            failure_message: failure_message,
            current_attempts: 0
          }
        end

        # Clear all failure patterns
        def clear_failure_patterns!
          self.failure_patterns = {}
          self.retry_tracking = {}
        end

        # Process a task synchronously (bypassing job queue)
        #
        # @param task [Tasker::Task] The task to process
        # @return [Boolean] True if task completed successfully
        def process_task_synchronously(task)
          return false unless active?

          log_execution("Starting synchronous processing for task #{task.task_id}")

          # Get task handler
          handler = Tasker::HandlerFactory.instance.get(task.name)

          # Process task using orchestration but synchronously
          begin
            result = handler.handle(task)
            log_execution("Completed synchronous processing for task #{task.task_id}: #{result}")
            true
          rescue StandardError => e
            log_execution("Failed synchronous processing for task #{task.task_id}: #{e.message}")
            false
          end
        end

        # Process multiple tasks in batch
        #
        # @param tasks [Array<Tasker::Task>] Tasks to process
        # @return [Hash] Results summary
        def process_tasks_batch(tasks)
          return {} unless active?

          results = {
            processed: 0,
            succeeded: 0,
            failed: 0,
            execution_time: 0
          }

          start_time = Time.current

          tasks.each do |task|
            results[:processed] += 1
            if process_task_synchronously(task)
              results[:succeeded] += 1
            else
              results[:failed] += 1
            end
          end

          results[:execution_time] = Time.current - start_time
          results
        end

        # Re-enqueue tasks for idempotency testing
        #
        # @param tasks [Array<Tasker::Task>] Tasks to re-enqueue
        # @param reset_steps [Boolean] Whether to reset step states
        def reenqueue_for_idempotency_test(tasks, reset_steps: false)
          return unless active?

          tasks.each do |task|
            log_execution("Re-enqueueing task #{task.task_id} for idempotency test")

            reset_task_steps_to_pending(task) if reset_steps

            # Process again to test idempotency
            process_task_synchronously(task)
          end
        end

        # Get execution statistics
        def execution_stats
          {
            total_executions: execution_log.size,
            recent_executions: execution_log.last(10),
            failure_patterns_active: failure_patterns.keys,
            retry_tracking: retry_tracking
          }
        end

        private

        # Log execution for debugging and analysis
        def log_execution(message)
          execution_log << {
            timestamp: Time.current,
            message: message,
            thread_id: Thread.current.object_id
          }

          Rails.logger.info("[TestCoordinator] #{message}")
        end

        # Reset task steps to pending state for re-execution
        def reset_task_steps_to_pending(task)
          task.workflow_steps.each do |step|
            # Clear existing transitions
            step.workflow_step_transitions.destroy_all

            # Create fresh pending state
            step.workflow_step_transitions.create!(
              to_state: Tasker::Constants::WorkflowStepStatuses::PENDING,
              sort_key: 0,
              most_recent: true,
              metadata: { reset_by: 'test_coordinator' }
            )

            # Reset step attributes
            step.update_columns(
              processed: false,
              in_process: false,
              processed_at: nil,
              attempts: 0,
              results: {}
            )
          end
        end

        # Patch TaskRunnerJob to use synchronous processing in test mode
        def patch_task_runner_job!
          return unless defined?(Tasker::TaskRunnerJob)

          original_perform = Tasker::TaskRunnerJob.instance_method(:perform)

          Tasker::TaskRunnerJob.define_method(:perform) do |task_id|
            if Tasker::Orchestration::TestCoordinator.active?
              # Synchronous processing - don't actually enqueue
              task = Tasker::Task.find(task_id)
              Tasker::Orchestration::TestCoordinator.process_task_synchronously(task)
            else
              # Normal processing
              original_perform.bind_call(self, task_id)
            end
          end
        end

        # Restore original TaskRunnerJob behavior
        def restore_task_runner_job!
          # In a real implementation, we'd need to store the original method
          # For now, we'll just ensure the coordinator is deactivated
          # The patching approach above handles this via the active? check
        end
      end

      # Instance methods for step-level failure injection

      # Check if a step should fail for testing
      #
      # @param step_name [String] The step name to check
      # @return [Boolean, String] False if should succeed, failure message if should fail
      def should_step_fail?(step_name)
        return false unless self.class.active?

        pattern = self.class.failure_patterns[step_name]
        return false unless pattern

        pattern[:current_attempts] += 1

        if pattern[:current_attempts] <= pattern[:failure_count]
          self.class.retry_tracking[step_name] ||= 0
          self.class.retry_tracking[step_name] += 1
          pattern[:failure_message]
        else
          false
        end
      end

      # Mark a step as succeeded (for failure pattern tracking)
      def mark_step_success(step_name)
        pattern = self.class.failure_patterns[step_name]
        return unless pattern

        self.class.log_execution("Step #{step_name} succeeded after #{pattern[:current_attempts]} attempts")
      end
    end
  end
end
