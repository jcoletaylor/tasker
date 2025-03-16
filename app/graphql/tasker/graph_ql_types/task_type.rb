# typed: strict
# frozen_string_literal: true

module Tasker
  module GraphQLTypes
    class TaskType < GraphQLTypes::BaseObject
      implements TaskInterface
      
      extend T::Sig
      field :named_task_id, Integer, null: false
      field :complete, Boolean, null: false
      field :requested_at, GraphQL::Types::ISO8601DateTime, null: false
      field :initiator, String, null: true
      field :source_system, String, null: true
      field :bypass_steps, GraphQL::Types::JSON, null: true
      field :context, GraphQL::Types::JSON, null: true, resolver_method: :resolve_context
      field :identity_hash, String, null: false
      field :named_task, GraphQLTypes::NamedTaskType, null: true
      field :workflow_steps, [GraphQLTypes::WorkflowStepType], null: false
      field :task_annotations, [GraphQLTypes::TaskAnnotationType], null: false

      sig { returns(Symbol) }
      def resolve_context
        :context
      end
    end
  end
end
