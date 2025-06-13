# frozen_string_literal: true

module Tasker
  # TaskExecutionContext now uses SQL functions for high-performance queries
  # This class explicitly delegates to the function-based implementation for better maintainability
  class TaskExecutionContext
    # Explicit delegation of class methods to function-based implementation
    def self.find(task_id)
      Tasker::Functions::FunctionBasedTaskExecutionContext.find(task_id)
    end

    def self.for_tasks(task_ids)
      Tasker::Functions::FunctionBasedTaskExecutionContext.for_tasks(task_ids)
    end

    # For backward compatibility, maintain the active method but point to function-based implementation
    def self.active
      Tasker::Functions::FunctionBasedTaskExecutionContext
    end
  end
end
