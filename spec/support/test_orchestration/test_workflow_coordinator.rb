# frozen_string_literal: true

require_relative '../../../lib/tasker/orchestration/workflow_coordinator'

module TestOrchestration
  # TestWorkflowCoordinator extends WorkflowCoordinator with retry logic for testing
  #
  # This coordinator implements the same execution loop as the production coordinator
  # but adds retry capabilities that work with the database views to test the complete
  # workflow execution path including failure recovery.
  class TestWorkflowCoordinator < Tasker::Orchestration::WorkflowCoordinator
    attr_reader :max_retry_attempts, :execution_log

    # Initialize test coordinator with retry capabilities
    #
    # @param reenqueuer_strategy [Object] Strategy for handling task reenqueuing
    # @param max_retry_attempts [Integer] Maximum number of retry attempts per task
    def initialize(reenqueuer_strategy: nil, max_retry_attempts: 5)
      super(reenqueuer_strategy: reenqueuer_strategy)
      @max_retry_attempts = max_retry_attempts
      @execution_log = []
    end

    # Execute workflow with retry logic
    #
    # This method wraps the standard workflow execution with retry capabilities,
    # allowing failed tasks to be retried based on database view readiness calculations.
    #
    # @param task [Tasker::Task] The task to execute
    # @param task_handler [Object] The task handler instance for delegation
    # @return [Boolean] True if task completed successfully
    def execute_workflow_with_retries(task, task_handler)
      attempts = 0
      success = false

      loop do
        attempts += 1
        log_execution("Starting execution attempt #{attempts}/#{max_retry_attempts} for task #{task.task_id}")

        # Execute the workflow once using the standard logic
        execute_workflow(task, task_handler)

        # Check if task completed successfully
        task.reload
        if task.status == Tasker::Constants::TaskStatuses::COMPLETE
          success = true
          log_execution("Task #{task.task_id} completed successfully after #{attempts} attempts")
          break
        end

        # Check if we've exceeded max attempts
        if attempts >= max_retry_attempts
          log_execution("Task #{task.task_id} exhausted max retry attempts (#{max_retry_attempts})")
          break
        end

        # Check if task has failed steps that can be retried
        failed_steps = task.workflow_steps.joins(:workflow_step_transitions)
                           .where(workflow_step_transitions: { most_recent: true, to_state: 'error' })

        if failed_steps.empty?
          log_execution("Task #{task.task_id} has no failed steps to retry")
          # If no failed steps and task isn't complete, it might be in a final state
          # Check if task is in a final state that should be considered success
          task.reload # Make sure we have the latest state
          log_execution("Task #{task.task_id} current status: #{task.status}")

          # Debug: Show ALL transitions to find the issue
          all_transitions = task.task_transitions.order(:sort_key)
          log_execution("Task #{task.task_id} has #{all_transitions.count} total transitions:")
          all_transitions.each do |transition|
            log_execution("Task #{task.task_id} transition: #{transition.from_state} -> #{transition.to_state} (sort_key: #{transition.sort_key}, most_recent: #{transition.most_recent})")
          end

          # Show what the state machine thinks is the current state
          log_execution("Task #{task.task_id} state_machine.current_state: #{task.state_machine.current_state}")

          if [Tasker::Constants::TaskStatuses::COMPLETE,
              Tasker::Constants::TaskStatuses::RESOLVED_MANUALLY].include?(task.status)
            success = true
            log_execution("Task #{task.task_id} is in final success state: #{task.status}")
          else
            log_execution("Task #{task.task_id} is not in a success state: #{task.status}")
          end
          break
        end

        # Check if any failed steps are eligible for retry (haven't exceeded retry limits)
        retryable_steps = failed_steps.select { |step| step.attempts < (step.retry_limit || 3) }

        if retryable_steps.empty?
          log_execution("Task #{task.task_id} has #{failed_steps.count} failed steps but none are retryable (exceeded retry limits)")
          break
        end

        log_execution("Task #{task.task_id} has #{retryable_steps.count} retryable failed steps, preparing for retry")

        # Reset task to pending for retry (this is what the reenqueuer would do)
        reset_task_for_retry(task)

        # Small delay to allow database views to update
        sleep(0.01)
      end

      log_execution("Completed workflow execution for task #{task.task_id}: #{success ? 'SUCCESS' : 'FAILED'} after #{attempts} attempts")
      success
    end

    # Get execution statistics for analysis
    #
    # @return [Hash] Execution statistics
    def execution_stats
      {
        total_executions: execution_log.size,
        recent_executions: execution_log.last(10)
      }
    end

    private

    # Get task execution context with error handling
    #
    # @param task_id [Integer] The task ID
    # @return [Tasker::TaskExecutionContext, nil] The execution context or nil
    def get_task_execution_context(task_id)
      Tasker::TaskExecutionContext.find(task_id)
    rescue ActiveRecord::RecordNotFound
      log_execution("TaskExecutionContext not found for task #{task_id}")
      nil
    end

    # Reset task to pending state for retry
    #
    # This simulates what the reenqueuer would do in production
    #
    # @param task [Tasker::Task] The task to reset
    def reset_task_for_retry(task)
      # Reset failed steps to pending state so they can be retried
      failed_steps = task.workflow_steps.joins(:workflow_step_transitions)
                         .where(workflow_step_transitions: { most_recent: true, to_state: 'error' })

      failed_steps.each do |step|
        # First, update all existing transitions to not be most_recent
        step.workflow_step_transitions.update_all(most_recent: false)

        # Then create new transition to pending state for the step
        step.workflow_step_transitions.create!(
          to_state: 'pending',
          sort_key: step.workflow_step_transitions.maximum(:sort_key).to_i + 1,
          most_recent: true,
          metadata: { reset_by: 'test_workflow_coordinator_retry' }
        )

        # Reset step flags to make it eligible for retry
        # This matches the StepExecutor error completion logic
        step.update_columns(
          processed: false,
          in_process: false,
          processed_at: nil
        )

        log_execution("Reset step #{step.name} (#{step.workflow_step_id}) to pending for retry")
      end

      # First, update all existing task transitions to not be most_recent
      task.task_transitions.update_all(most_recent: false)

      # Then create new transition to pending state for the task
      task.task_transitions.create!(
        to_state: Tasker::Constants::TaskStatuses::PENDING,
        sort_key: task.task_transitions.maximum(:sort_key).to_i + 1,
        most_recent: true,
        metadata: { reset_by: 'test_workflow_coordinator_retry' }
      )

      # Reload task to reflect changes
      task.reload
      log_execution("Reset task #{task.task_id} to pending for retry (reset #{failed_steps.count} failed steps)")
    end

    # Log execution for debugging and analysis
    #
    # @param message [String] The message to log
    def log_execution(message)
      execution_log << {
        timestamp: Time.current,
        message: message,
        thread_id: Thread.current.object_id
      }

      Rails.logger.info("[TestWorkflowCoordinator] #{message}")
    end
  end
end
