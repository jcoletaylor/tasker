# typed: strict
# frozen_string_literal: true

module Tasker
  module Types
    class NamedTasksNamedStepType < Types::BaseObject
      field :id, ID, null: false
      field :named_task_id, Integer, null: false
      field :named_step_id, Integer, null: false
      field :skippable, Boolean, null: false
      field :default_retryable, Boolean, null: false
      field :default_retry_limit, Integer, null: false
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
      field :named_task, Types::NamedTaskType, null: true
      field :named_step, Types::NamedStepType, null: true
    end
  end
end
