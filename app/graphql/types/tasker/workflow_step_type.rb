# typed: strict
# frozen_string_literal: true

module Tasker
  module Types
    class WorkflowStepType < Types::BaseObject
      field :workflow_step_id, ID, null: false
      field :task_id, Integer, null: false
      field :named_step_id, Integer, null: false
      field :depends_on_step_id, Integer, null: true
      field :status, String, null: false
      field :retryable, Boolean, null: false
      field :retry_limit, Integer, null: true
      field :in_process, Boolean, null: false
      field :processed, Boolean, null: false
      field :processed_at, GraphQL::Types::ISO8601DateTime, null: true
      field :attempts, Integer, null: true
      field :last_attempted_at, GraphQL::Types::ISO8601DateTime, null: true
      field :backoff_request_seconds, Integer, null: true
      field :inputs, GraphQL::Types::JSON, null: true
      field :results, GraphQL::Types::JSON, null: true
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
      field :skippable, Boolean, null: false
      field :task, Types::TaskType, null: true
      field :named_step, [Types::NamedStepType], null: true
      field :depends_on_step, [Types::WorkflowStepType], null: true
    end
  end
end
