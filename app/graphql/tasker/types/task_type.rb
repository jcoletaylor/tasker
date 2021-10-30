# typed: strict
# frozen_string_literal: true

module Tasker
  module Types
    class TaskType < Types::BaseObject
      extend T::Sig
      field :task_id, ID, null: false
      field :named_task_id, Integer, null: false
      field :status, String, null: false
      field :complete, Boolean, null: false
      field :requested_at, GraphQL::Types::ISO8601DateTime, null: false
      field :initiator, String, null: true
      field :source_system, String, null: true
      field :reason, String, null: true
      field :bypass_steps, GraphQL::Types::JSON, null: true
      field :tags, GraphQL::Types::JSON, null: true
      field :context, GraphQL::Types::JSON, null: true, resolver_method: :resolve_context
      field :identity_hash, String, null: false
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
      field :named_task, Types::NamedTaskType, null: true
      field :workflow_steps, [Types::WorkflowStepType], null: false
      field :task_annotations, [Types::TaskAnnotationType], null: false

      sig { returns(Symbol) }
      def resolve_context
        :context
      end
    end
  end
end
