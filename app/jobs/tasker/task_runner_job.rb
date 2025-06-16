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
      task = Tasker::Task.where(task_id: task_id).first
      return unless task

      Rails.logger.info "TaskRunnerJob: Starting execution for task #{task_id}"

      # Get the appropriate task handler and process the task
      handler = handler_factory.get(task.name)
      handler.handle(task)

      # Check if task completed successfully
      task.reload
      unless task.status == Tasker::Constants::TaskStatuses::COMPLETE
        Rails.logger.error "TaskRunnerJob: Task did not complete successfully for task #{task_id}, status: #{task.status}"
        raise "Task processing failed for task #{task_id} - final status: #{task.status}"
      end

      Rails.logger.info "TaskRunnerJob: Completed execution for task #{task_id}"
    rescue StandardError => e
      Rails.logger.error "TaskRunnerJob: Error processing task #{task_id}: #{e.message}"
      raise
    end
  end
end
