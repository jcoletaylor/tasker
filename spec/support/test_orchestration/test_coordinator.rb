# frozen_string_literal: true

require_relative 'test_reenqueuer'

module TestOrchestration
  # TestCoordinator provides test-specific orchestration that works WITH the
  # core orchestration system rather than bypassing it
  #
  # This coordinator:
  # - Processes tasks synchronously using the real orchestration logic
  # - Implements proper retry loops that respect the database views
  # - Uses TestReenqueuer strategy to manage retries without ActiveJob
  # - Provides detailed metrics and logging for test analysis
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

        # Activate test reenqueuer
        TestReenqueuer.activate!

        # Patch TaskReenqueuer to use TestReenqueuer strategy
        patch_task_reenqueuer!
      end

      # Deactivate test coordination (restore normal behavior)
      def deactivate!
        self.active = false
        TestReenqueuer.deactivate!
        restore_task_reenqueuer!
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
        self.retry_tracking = {}
        TestReenqueuer.clear_retry_queue!
      end

      # Process a task with proper retry loop until completion or exhaustion
      #
      # This method delegates to TestWorkflowCoordinator's proven retry logic
      #
      # @param task [Tasker::Task] The task to process
      # @param max_attempts [Integer] Maximum retry attempts
      # @return [Boolean] True if task completed successfully
      def process_task_until_complete(task, max_attempts: 10)
        return false unless active?

        log_execution("Starting complete processing for task #{task.task_id} (max_attempts: #{max_attempts})")

        # Automatically bypass backoff timing and reset failed steps for test environment
        bypass_backoff_for_testing([task])
        reset_failed_steps_for_retry([task])

        # Get task handler using the base name (strip unique suffix)
        handler_name = extract_base_handler_name(task.name)
        handler = Tasker::HandlerFactory.instance.get(handler_name)

        unless handler
          log_execution("No task handler found for task #{task.task_id} (handler: #{handler_name})")
          return false
        end

        begin
          # Configure the handler to use test strategies for synchronous processing
          handler.workflow_coordinator_strategy = TestOrchestration::TestWorkflowCoordinator
          handler.reenqueuer_strategy = TestOrchestration::TestReenqueuer

          # Create TestWorkflowCoordinator instance with proper retry settings
          test_coordinator = TestOrchestration::TestWorkflowCoordinator.new(
            reenqueuer_strategy: TestOrchestration::TestReenqueuer.new,
            max_retry_attempts: max_attempts
          )

          # Use TestWorkflowCoordinator's proven retry logic
          success = test_coordinator.execute_workflow_with_retries(task, handler)

          # Track retry statistics from TestWorkflowCoordinator
          update_retry_tracking(task, test_coordinator)

          log_execution("Completed processing for task #{task.task_id}: #{success ? 'SUCCESS' : 'FAILED'}")
          success
        rescue StandardError => e
          log_execution("Error processing task #{task.task_id}: #{e.message}")
          false
        end
      end

      # Process multiple tasks with retry logic
      def process_tasks_with_retries(tasks, max_attempts: 10)
        return {} unless active?

        results = {
          total_workflows: tasks.count,
          successful_workflows: 0,
          failed_workflows: 0,
          total_execution_time: 0,
          total_steps_processed: 0
        }

        start_time = Time.current

        tasks.each do |task|
          success = process_task_until_complete(task, max_attempts: max_attempts)

          if success
            results[:successful_workflows] += 1
          else
            results[:failed_workflows] += 1
          end

          # Count processed steps
          task.reload
          results[:total_steps_processed] += task.workflow_steps.count(&:processed)
        end

        results[:total_execution_time] = Time.current - start_time
        results[:average_execution_time] = results[:total_execution_time] / tasks.count if tasks.count > 0
        results
      end

      # Process a single task synchronously (alias for process_task_until_complete)
      def process_task_synchronously(task, max_attempts: 10)
        process_task_until_complete(task, max_attempts: max_attempts)
      end

      # Process multiple tasks in batch
      def process_tasks_batch(tasks, max_attempts: 10)
        results = process_tasks_with_retries(tasks, max_attempts: max_attempts)

        # Convert to expected format
        {
          processed: results[:total_workflows],
          succeeded: results[:successful_workflows],
          failed: results[:failed_workflows],
          execution_time: results[:total_execution_time]
        }
      end

      # Reenqueue tasks for idempotency testing
      def reenqueue_for_idempotency_test(tasks, reset_steps: true)
        return unless active?

        tasks.each do |task|
          next unless reset_steps

          # Reset all steps to pending state - handle completed steps specially
          task.workflow_steps.each do |step|
            current_state = step.state_machine.current_state

            # For completed steps, we need to create a new transition directly
            # since the state machine doesn't allow complete -> pending transitions
            if current_state == Tasker::Constants::WorkflowStepStatuses::COMPLETE
              # Update all existing transitions to not be most_recent
              step.workflow_step_transitions.update_all(most_recent: false)

              # Create new transition to pending state for idempotency testing
              step.workflow_step_transitions.create!(
                to_state: Tasker::Constants::WorkflowStepStatuses::PENDING,
                sort_key: step.workflow_step_transitions.maximum(:sort_key).to_i + 1,
                most_recent: true,
                metadata: { reset_by: 'idempotency_test', previous_state: current_state }
              )
            else
              # For non-completed steps, use safe transitions
              step.extend(Tasker::Concerns::IdempotentStateTransitions)
              step.safe_transition_to(step, Tasker::Constants::WorkflowStepStatuses::PENDING)
            end

            # Reset step flags
            step.update_columns(
              processed: false,
              in_process: false,
              processed_at: nil
            )
          end

          # Reset task to pending state - handle completed tasks specially
          current_task_state = task.status
          if current_task_state == Tasker::Constants::TaskStatuses::COMPLETE
            # Update all existing transitions to not be most_recent
            task.task_transitions.update_all(most_recent: false)

            # Create new transition to pending state for idempotency testing
            task.task_transitions.create!(
              to_state: Tasker::Constants::TaskStatuses::PENDING,
              sort_key: task.task_transitions.maximum(:sort_key).to_i + 1,
              most_recent: true,
              metadata: { reset_by: 'idempotency_test', previous_state: current_task_state }
            )
          else
            # For non-completed tasks, use safe transitions
            task.extend(Tasker::Concerns::IdempotentStateTransitions)
            task.safe_transition_to(task, Tasker::Constants::TaskStatuses::PENDING)
          end

          task.reload
          log_execution("Reset task #{task.task_id} for idempotency test")
        end
      end

      # Simulate time passage for backoff logic by aging error transitions
      # This makes failed steps eligible for retry by making their failure timestamps old enough
      def simulate_backoff_time_passage(tasks, age_seconds: 60)
        return unless active?

        tasks.each do |task|
          task.workflow_steps.each do |step|
            # Find error transitions that are blocking retry due to backoff
            error_transitions = step.workflow_step_transitions
                                    .where(to_state: 'error')
                                    .where('created_at > ?', age_seconds.seconds.ago)

            next unless error_transitions.any?

            # Age the error transitions to simulate time passage
            aged_time = age_seconds.seconds.ago
            error_transitions.update_all(created_at: aged_time, updated_at: aged_time)

            log_execution("Aged #{error_transitions.count} error transitions for step #{step.workflow_step_id} by #{age_seconds} seconds")
          end
        end
      end

      # Reset failed steps to be ready for retry by manipulating their state correctly
      def reset_failed_steps_for_retry(tasks)
        return unless active?

        reset_count = 0
        tasks.each do |task|
          failed_steps = task.workflow_steps.joins(:workflow_step_transitions)
                             .where(tasker_workflow_step_transitions: {
                                      to_state: 'error',
                                      most_recent: true
                                    })

          failed_steps.each do |step|
            # Age the error transition to make it eligible for retry
            error_transition = step.workflow_step_transitions
                                   .where(to_state: 'error', most_recent: true)
                                   .first

            next unless error_transition

            # Make the error old enough to pass backoff check (60 seconds ago)
            aged_time = 60.seconds.ago
            error_transition.update_columns(
              created_at: aged_time,
              updated_at: aged_time
            )

            # Also reset the step to pending state for retry
            # Update the error transition to not be most_recent
            error_transition.update_column(:most_recent, false)

            # Create a new pending transition
            step.workflow_step_transitions.create!(
              to_state: Tasker::Constants::WorkflowStepStatuses::PENDING,
              sort_key: step.workflow_step_transitions.maximum(:sort_key).to_i + 1,
              most_recent: true,
              metadata: { reset_by: 'test_backoff_simulation', previous_state: 'error' }
            )

            # Reset step processing flags
            step.update_columns(
              processed: false,
              in_process: false,
              processed_at: nil
            )

            reset_count += 1
            log_execution("Reset failed step #{step.workflow_step_id} (#{step.name}) to pending for retry eligibility")
          end
        end

        log_execution("Reset #{reset_count} failed steps across #{tasks.count} tasks for retry eligibility")
        reset_count
      end

      # Bypass backoff timing for all failed steps in test environment
      # This makes failed steps immediately eligible for retry
      def bypass_backoff_for_testing(tasks)
        return unless active?

        bypassed_count = 0
        tasks.each do |task|
          # Find all error transitions that might be blocking retry due to backoff
          error_transitions = Tasker::WorkflowStepTransition.joins(:workflow_step)
                                                            .where(tasker_workflow_steps: { task_id: task.task_id })
                                                            .where(to_state: 'error')
                                                            .where('tasker_workflow_step_transitions.created_at > ?', 60.seconds.ago)

          next unless error_transitions.any?

          # Age all error transitions to bypass backoff
          aged_time = 60.seconds.ago
          error_transitions.update_all(created_at: aged_time, updated_at: aged_time)
          bypassed_count += error_transitions.count

          log_execution("Bypassed backoff for #{error_transitions.count} error transitions in task #{task.task_id}")
        end

        log_execution("Bypassed backoff timing for #{bypassed_count} error transitions across #{tasks.count} tasks")
        bypassed_count
      end

      # Get execution statistics
      def execution_stats
        {
          total_executions: execution_log.size,
          recent_executions: execution_log.last(10),
          failure_patterns_active: failure_patterns.keys,
          retry_tracking: retry_tracking || {},
          retry_queue_size: TestReenqueuer.retry_queue_size
        }
      end

      private

      # Process a task once using the real orchestration system
      def process_task_once(task)
        # Get task handler using the base name (strip unique suffix)
        handler_name = extract_base_handler_name(task.name)
        handler = Tasker::HandlerFactory.instance.get(handler_name)
        return false unless handler

        begin
          # Configure the handler to use test strategies for synchronous processing
          # This ensures failed steps are properly handled for retry
          handler.workflow_coordinator_strategy = TestOrchestration::TestWorkflowCoordinator
          handler.reenqueuer_strategy = TestOrchestration::TestReenqueuer

          # Use the real task handler with orchestration
          handler.handle(task)

          # Reload and check final status
          task.reload
          success = task.status == Tasker::Constants::TaskStatuses::COMPLETE

          log_execution("Single processing attempt for task #{task.task_id}: #{success ? 'SUCCESS' : 'FAILED'} (status: #{task.status})")
          success
        rescue StandardError => e
          log_execution("Failed single processing attempt for task #{task.task_id}: #{e.message}")
          false
        end
      end

      # Process tasks from the retry queue
      def process_retry_queue
        retry_entries = TestReenqueuer.pending_retries
        TestReenqueuer.clear_retry_queue!

        retry_entries.each do |entry|
          task = entry[:task]
          reason = entry[:reason]

          log_execution("Processing retry queue entry for task #{task.task_id} (reason: #{reason})")

          # The task should already be in the correct state for retry
          # Just process it once - if it needs more retries, it will be re-added to queue
          process_task_once(task)
        end
      end

      # Get task execution context with error handling
      def get_task_execution_context(task_id)
        Tasker::TaskExecutionContext.find(task_id)
      rescue ActiveRecord::RecordNotFound
        log_execution("TaskExecutionContext not found for task #{task_id}")
        nil
      end

      # Get the earliest retry time for failed steps in a task
      def get_earliest_retry_time(task_id)
        # Query the step readiness view for failed steps with next_retry_at
        readiness_records = Tasker::StepReadinessStatus.joins(:workflow_step)
                                                       .where(tasker_workflow_steps: { task_id: task_id })
                                                       .where(current_state: 'error')
                                                       .where.not(next_retry_at: nil)

        readiness_records.minimum(:next_retry_at)
      end

      # Extract base handler name by removing unique suffix
      def extract_base_handler_name(task_name)
        # Remove the unique suffix pattern: _timestamp_randomnumber
        # e.g., "linear_workflow_task_1749555645_529" -> "linear_workflow_task"
        task_name.gsub(/_\d+_\d+$/, '')
      end

      # Update retry tracking statistics from TestWorkflowCoordinator
      def update_retry_tracking(task, test_coordinator)
        stats = test_coordinator.execution_stats

        # Initialize retry_tracking if not already done
        self.retry_tracking ||= {}

        # Track by task_id for task-level tracking
        retry_tracking[task.task_id] = {
          execution_log: stats[:recent_executions] || [],
          total_executions: stats[:total_executions] || 0,
          task_name: task.name,
          final_status: task.status
        }

        # Track step-level retry counts for test expectations
        # Parse the execution log to extract step-level retry information
        stats[:recent_executions]&.each do |log_entry|
          message = log_entry[:message]

          # Look for step reset messages to identify retried steps
          # Extract step name from message like "Reset step process_data (43146) to pending for retry"
          unless message.include?('Reset step') && message.include?('to pending for retry') && (match = message.match(/Reset step (\w+) \(\d+\) to pending for retry/))
            next
          end

          step_name = match[1]
          # Store simple retry count for step names (what tests expect)
          retry_tracking[step_name] = (retry_tracking[step_name] || 0) + 1
        end

        # Also track configured failure patterns as retries
        failure_patterns.each do |step_name, config|
          if config[:current_attempts] && config[:current_attempts] > 1
            retry_tracking[step_name] = config[:current_attempts] - 1
          end
        end
      end

      # Log execution for debugging and analysis
      def log_execution(message)
        execution_log << {
          timestamp: Time.current,
          message: message,
          thread_id: Thread.current.object_id
        }

        Rails.logger.info("[TestCoordinator] #{message}")
      end

      # Patch TaskReenqueuer to use TestReenqueuer strategy
      def patch_task_reenqueuer!
        return unless defined?(Tasker::Orchestration::TaskReenqueuer)

        # Store original methods
        @original_reenqueue_task = Tasker::Orchestration::TaskReenqueuer.instance_method(:reenqueue_task)
        @original_reenqueue_task_delayed = Tasker::Orchestration::TaskReenqueuer.instance_method(:reenqueue_task_delayed)

        # Replace with test strategy
        Tasker::Orchestration::TaskReenqueuer.define_method(:reenqueue_task) do |task, reason: 'test_retry'|
          if TestOrchestration::TestCoordinator.active?
            test_reenqueuer = TestOrchestration::TestReenqueuer.new
            test_reenqueuer.reenqueue_task(task, reason: reason)
          else
            TestOrchestration::TestCoordinator.instance_variable_get(:@original_reenqueue_task).bind_call(self, task, reason: reason)
          end
        end

        Tasker::Orchestration::TaskReenqueuer.define_method(:reenqueue_task_delayed) do |task, delay_seconds:, reason: 'test_delayed_retry'|
          if TestOrchestration::TestCoordinator.active?
            test_reenqueuer = TestOrchestration::TestReenqueuer.new
            test_reenqueuer.reenqueue_task_delayed(task, delay_seconds: delay_seconds, reason: reason)
          else
            TestOrchestration::TestCoordinator.instance_variable_get(:@original_reenqueue_task_delayed).bind_call(self, task, delay_seconds: delay_seconds, reason: reason)
          end
        end
      end

      # Restore original TaskReenqueuer behavior
      def restore_task_reenqueuer!
        return unless defined?(Tasker::Orchestration::TaskReenqueuer)
        return unless @original_reenqueue_task && @original_reenqueue_task_delayed

        # Restore original methods
        Tasker::Orchestration::TaskReenqueuer.define_method(:reenqueue_task, @original_reenqueue_task)
        Tasker::Orchestration::TaskReenqueuer.define_method(:reenqueue_task_delayed, @original_reenqueue_task_delayed)
      end
    end
  end
end
