# typed: true
# frozen_string_literal: true

module Tasker
  class TaskRunnerJob
    include Sidekiq::Worker
    sidekiq_options retry: 3, backtrace: true, queue: :default

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
