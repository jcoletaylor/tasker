# typed: false
# frozen_string_literal: true

module Tasker
  class TaskRunnerJob < Tasker::ApplicationJob
    queue_as :default
    retry_on StandardError, wait: 3.seconds, attempts: 3

    def handler_factory
      @handler_factory ||= Tasker::HandlerFactory.instance
    end

    def perform(task_id)
      # Clear any pending reenqueue tracking when job starts
      # This ensures we don't have stale tracking entries
      if defined?(Tasker::Orchestration::TaskFinalizer)
        Tasker::Orchestration::TaskFinalizer.complete_reenqueue(task_id)
      end

      task = Tasker::Task.where(task_id: task_id).first
      return unless task

      Rails.logger.info "TaskRunnerJob: Starting execution for task #{task_id}"

      # Since orchestration is guaranteed to be initialized at startup,
      # we can directly use it without fallback checks
      Rails.logger.debug "TaskRunnerJob: Using event-driven orchestration for task #{task_id}"
      result = Tasker::Orchestration::Coordinator.process_task(task_id)

      unless result
        Rails.logger.error "TaskRunnerJob: Orchestration processing failed for task #{task_id}"
        # Don't fall back to old handler - this indicates a real error that should be investigated
        raise "Orchestration processing failed for task #{task_id}"
      end

      Rails.logger.info "TaskRunnerJob: Completed execution for task #{task_id}"
    rescue StandardError => e
      Rails.logger.error "TaskRunnerJob: Error processing task #{task_id}: #{e.message}"
      Tasker::Orchestration::TaskFinalizer.complete_reenqueue(task_id)
      raise
    end
  end
end
