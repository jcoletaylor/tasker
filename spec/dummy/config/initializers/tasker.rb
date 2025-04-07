# typed: strict
# frozen_string_literal: true

# This initializer ensures that all task handlers are loaded and registered
# after the Tasker gem is initialized. Applications using the Tasker gem
# should include a similar initializer to properly load their task handlers.
#
# The initializer uses Rails' autoloading patterns to find and load all task
# handler classes. It then ensures they are properly registered with the
# Tasker::HandlerFactory.

require 'tasker'

Rails.application.config.after_initialize do
  # Force eager loading of task handlers in production
  if Rails.env.production? && Rails.root.join('app/tasks').exist? && Rails.root.join('app/tasks').exist?
    T.unsafe(Rails.autoloaders.main).eager_load_dir(
      Rails.root.join('app/tasks')
    )
  end

  # Ensure all handlers that include Tasker::TaskHandler are registered
  Rails.autoloaders.main.on_load do |_const, path|
    next unless path&.to_s&.include?('/tasks/')

    klasses = ObjectSpace.each_object(Class).select do |klass|
      klass < Tasker::TaskHandler
    rescue StandardError
      false
    end

    klasses.each do |klass|
      T.unsafe(klass).register_handler if klass.respond_to?(:register_handler)
    end
  end
end
