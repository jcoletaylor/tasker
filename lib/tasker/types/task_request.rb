# typed: false
# frozen_string_literal: true

module Tasker
  module Types
    # TaskRequest represents a request to perform a task within the system
    # It contains all the necessary information to identify, track, and execute a task
    class TaskRequest < Dry::Struct
      # The name of the task to be performed
      # @return [String]
      attribute :name, Types::Strict::String

      # Context data required for task execution, containing task-specific information
      # @return [Hash]
      attribute :context, Types::Hash

      # Current status of the task (e.g., PENDING, IN_PROGRESS, COMPLETED, FAILED)
      # @return [String]
      attribute :status, Types::String.default(Constants::TaskStatuses::PENDING)

      # The entity or system that initiated this task request
      # @return [String]
      attribute :initiator, Types::String.default(Constants::UNKNOWN)

      # The system from which this task originated
      # @return [String]
      attribute :source_system, Types::String.default(Constants::UNKNOWN)

      # The reason why this task was requested
      # @return [String]
      attribute :reason, Types::String.default(Constants::UNKNOWN)

      # Indicates whether the task has been completed
      # @return [Boolean]
      attribute :complete, Types::Bool.default(false)

      # Tags associated with this task for categorization or filtering
      # @return [Array<String>]
      attribute :tags, Types::Array.of(Types::String).default([].freeze)

      # List of step names that should be bypassed during task execution
      # @return [Array<String>]
      attribute :bypass_steps, Types::Array.of(Types::String).default([].freeze)

      # Timestamp when the task was initially requested
      # @return [Time]
      attribute(:requested_at, Types::JSON::Time.default { Time.zone.now })
    end
  end
end

