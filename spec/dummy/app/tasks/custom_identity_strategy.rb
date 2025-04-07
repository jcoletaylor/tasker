# frozen_string_literal: true

require 'securerandom'

# A custom identity strategy for testing purposes
class CustomIdentityStrategy < Tasker::IdentityStrategy
  def generate_identity_hash(task, _task_options)
    # This is just a different implementation that still uses UUID
    # but demonstrates using the task object
    "custom-#{task.class.name.demodulize.downcase}-#{SecureRandom.uuid}"
  end
end
