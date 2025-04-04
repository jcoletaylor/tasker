# typed: true
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
      handler = handler_factory.get(task.name)
      handler.handle(task)
    end
  end
end
