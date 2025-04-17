# frozen_string_literal: true

require 'securerandom'
require 'digest'

module Tasker
  # Base identity strategy class that generates a GUID by default
  #
  # Identity strategies are used to generate unique identifiers for tasks.
  # This allows for customizing how task identity is determined and tracked.
  class IdentityStrategy
    # Generate a unique identity hash for a task
    #
    # The default implementation generates a random UUID.
    #
    # @param _task [Tasker::Task] The task to generate an identity for
    # @param _task_options [Hash] Additional options for identity generation
    # @return [String] A unique identity hash
    def generate_identity_hash(_task, _task_options)
      SecureRandom.uuid
    end
  end

  # Strategy that uses SHA256 hash of task identity options
  #
  # This strategy is useful when you want identical tasks (with the same
  # options/parameters) to have the same identity hash.
  class HashIdentityStrategy < IdentityStrategy
    # Generate a deterministic identity hash based on task options
    #
    # @param _task [Tasker::Task] The task to generate an identity for
    # @param task_options [Hash] Task options to hash for identity
    # @return [String] A SHA256 hash of the task options
    def generate_identity_hash(_task, task_options)
      Digest::SHA256.hexdigest(task_options.to_json)
    end
  end
end
