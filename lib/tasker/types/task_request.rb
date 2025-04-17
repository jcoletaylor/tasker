# typed: false
# frozen_string_literal: true

module Tasker
  module Types
    # TaskRequest represents a request to perform a task within the system
    #
    # It contains all the necessary information to identify, track, and execute a task
    # including context data, metadata, and configuration for the task execution.
    class TaskRequest < Dry::Struct
      # @!attribute [r] name
      #   @return [String] The name of the task to be performed
      attribute :name, Types::Strict::String

      # @!attribute [r] context
      #   @return [Hash] Context data required for task execution, containing task-specific information
      attribute :context, Types::Hash

      # @!attribute [r] status
      #   @return [String] Current status of the task (e.g., PENDING, IN_PROGRESS, COMPLETED, FAILED)
      attribute :status, Types::String.default(Constants::TaskStatuses::PENDING)

      # @!attribute [r] initiator
      #   @return [String] The entity or system that initiated this task request
      attribute :initiator, Types::String.default(Constants::UNKNOWN)

      # @!attribute [r] source_system
      #   @return [String] The system from which this task originated
      attribute :source_system, Types::String.default(Constants::UNKNOWN)

      # @!attribute [r] reason
      #   @return [String] The reason why this task was requested
      attribute :reason, Types::String.default(Constants::UNKNOWN)

      # @!attribute [r] complete
      #   @return [Boolean] Indicates whether the task has been completed
      attribute :complete, Types::Bool.default(false)

      # @!attribute [r] tags
      #   @return [Array<String>] Tags associated with this task for categorization or filtering
      attribute :tags, Types::Array.of(Types::String).default([].freeze)

      # @!attribute [r] bypass_steps
      #   @return [Array<String>] List of step names that should be bypassed during task execution
      attribute :bypass_steps, Types::Array.of(Types::String).default([].freeze)

      # @!attribute [r] requested_at
      #   @return [Time] Timestamp when the task was initially requested
      attribute(:requested_at, Types::JSON::Time.default { Time.zone.now })
    end
  end
end
