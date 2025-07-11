# frozen_string_literal: true

require_relative 'test_reenqueuer'

module TestOrchestration
  # TestCoordinator provides test-specific orchestration that follows the production path exactly
  #
  # This coordinator:
  # - Processes tasks following the exact production workflow
  # - Uses TestReenqueuer strategy for synchronous reenqueuing
  # - Validates actual production behavior rather than alternative logic
  # - Provides deterministic failure scenarios for testing
  class TestCoordinator
    include Tasker::Concerns::EventPublisher

    class << self
      attr_accessor :active, :execution_log, :failure_patterns

      # Activate test coordination mode
      def activate!
        self.active = true
        self.execution_log = []
        self.failure_patterns = {}

        # Activate test reenqueuer
        TestReenqueuer.activate!
      end

      # Deactivate test coordination (restore normal behavior)
      def deactivate!
        self.active = false
        TestReenqueuer.deactivate!
      end

      # Check if test coordination is active
      def active?
        !!@active
      end

      # Configure failure patterns for specific steps
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
        TestReenqueuer.clear_retry_queue!
      end

      # Process task following production path exactly
      #
      # This method uses actual production workflow with TestReenqueuer strategy
      # to validate the real production behavior synchronously
      #
      # @param task [Tasker::Task] The task to process
      # @return [Boolean] True if task completed successfully
      def process_task_production_path(task)
        return false unless active?

        log_execution("Starting production path processing for task #{task.task_id}")

        # Get task handler using the base name (strip unique suffix)
        handler_name = extract_base_handler_name(task.name)
        handler = Tasker::HandlerFactory.instance.get(handler_name)

        unless handler
          log_execution("No task handler found for task #{task.task_id} (handler: #{handler_name})")
          return false
        end

        begin
          # Configure handler to use test reenqueuer strategy for synchronous processing
          original_reenqueuer = handler.send(:reenqueuer_strategy)
          handler.reenqueuer_strategy = TestOrchestration::TestReenqueuer

          # Process task using actual production workflow
          # This will use the real WorkflowCoordinator, not TestWorkflowCoordinator
          handler.handle(task)

          # Process any reenqueued tasks synchronously until completion
          max_reenqueue_cycles = 10
          cycles = 0
          last_task_status = nil

          while TestReenqueuer.has_queued_tasks? && cycles < max_reenqueue_cycles
            # Check if task status changed - if not, we might be in an infinite loop
            task.reload
            current_status = task.status

            if last_task_status == current_status && current_status == 'pending'
              # Task status hasn't changed and it's pending - check if there are ready steps
              context = Tasker::Functions::FunctionBasedTaskExecutionContext.find(task.task_id)
              if context&.ready_steps == 0
                log_execution("Breaking reenqueue loop: Task #{task.task_id} has no ready steps (likely in backoff)")
                break
              end
            end

            last_task_status = current_status
            TestReenqueuer.process_queue!
            cycles += 1
          end

          if cycles >= max_reenqueue_cycles
            log_execution("Warning: Reached max reenqueue cycles (#{max_reenqueue_cycles}) for task #{task.task_id}")
          end

          # Check final result
          task.reload
          success = task.status == Tasker::Constants::TaskStatuses::COMPLETE

          log_execution("Completed production path processing for task #{task.task_id}: #{success ? 'SUCCESS' : 'FAILED'}")
          success
        rescue StandardError => e
          log_execution("Error processing task #{task.task_id}: #{e.message}")
          false
        ensure
          # Restore original reenqueuer strategy
          handler.reenqueuer_strategy = original_reenqueuer if handler && original_reenqueuer
        end
      end

      # Process multiple tasks following production path
      def process_tasks_production_path(tasks)
        return {} unless active?

        results = {
          total_workflows: tasks.count,
          successful_workflows: 0,
          failed_workflows: 0,
          total_execution_time: 0
        }

        start_time = Time.current

        tasks.each do |task|
          success = process_task_production_path(task)

          if success
            results[:successful_workflows] += 1
          else
            results[:failed_workflows] += 1
          end
        end

        results[:total_execution_time] = Time.current - start_time
        results[:average_execution_time] = results[:total_execution_time] / tasks.count if tasks.any?
        results
      end

      # Legacy method alias for backward compatibility
      def process_task_synchronously(task)
        process_task_production_path(task)
      end

      # Legacy method alias for backward compatibility
      def process_tasks_batch(tasks)
        results = process_tasks_production_path(tasks)

        # Convert to expected format
        {
          processed: results[:total_workflows],
          succeeded: results[:successful_workflows],
          failed: results[:failed_workflows],
          execution_time: results[:total_execution_time]
        }
      end

      private

      # Extract base handler name from task name (remove unique suffix)
      def extract_base_handler_name(task_name)
        # Remove the unique suffix pattern: _timestamp_randomnumber
        # e.g., "linear_workflow_task_1749555645_529" -> "linear_workflow_task"
        task_name.gsub(/_\d+_\d+$/, '')
      end

      # Log execution for debugging and analysis
      def log_execution(message)
        execution_log << {
          timestamp: Time.current,
          message: message,
          thread_id: Thread.current.object_id
        }

        Rails.logger.debug { "[TestCoordinator] #{message}" }
      end
    end
  end
end
