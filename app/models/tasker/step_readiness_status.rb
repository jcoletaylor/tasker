# frozen_string_literal: true

module Tasker
  # StepReadinessStatus now uses SQL functions for high-performance queries
  # This class explicitly delegates to the function-based implementation for better maintainability
  class StepReadinessStatus
    # Explicit delegation of class methods to function-based implementation
    def self.for_task(task_id, step_ids = nil)
      Tasker::Functions::FunctionBasedStepReadinessStatus.for_task(task_id, step_ids)
    end

    def self.for_steps(task_id, step_ids)
      Tasker::Functions::FunctionBasedStepReadinessStatus.for_steps(task_id, step_ids)
    end

    def self.for_tasks(task_ids)
      Tasker::Functions::FunctionBasedStepReadinessStatus.for_tasks(task_ids)
    end

    # Task-scoped methods that require task_id parameter
    def self.ready_for_task(task_id)
      Tasker::Functions::FunctionBasedStepReadinessStatus.ready_for_task(task_id)
    end

    def self.blocked_by_dependencies_for_task(task_id)
      Tasker::Functions::FunctionBasedStepReadinessStatus.blocked_by_dependencies_for_task(task_id)
    end

    def self.blocked_by_retry_for_task(task_id)
      Tasker::Functions::FunctionBasedStepReadinessStatus.blocked_by_retry_for_task(task_id)
    end

    def self.pending_for_task(task_id)
      Tasker::Functions::FunctionBasedStepReadinessStatus.pending_for_task(task_id)
    end

    def self.failed_for_task(task_id)
      Tasker::Functions::FunctionBasedStepReadinessStatus.failed_for_task(task_id)
    end

    def self.in_progress_for_task(task_id)
      Tasker::Functions::FunctionBasedStepReadinessStatus.in_progress_for_task(task_id)
    end

    def self.complete_for_task(task_id)
      Tasker::Functions::FunctionBasedStepReadinessStatus.complete_for_task(task_id)
    end

    # For backward compatibility, maintain the active method but point to function-based implementation
    def self.active
      Tasker::Functions::FunctionBasedStepReadinessStatus
    end
  end
end
