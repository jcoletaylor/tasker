# typed: false
# frozen_string_literal: true

module Tasker
  module GraphQLTypes
    class TaskAnnotationType < GraphQLTypes::BaseObject
      field :task_annotation_id, ID, null: false
      field :task_id, Integer, null: false
      field :annotation_type_id, Integer, null: false
      field :annotation, GraphQL::Types::JSON, null: true
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
      field :task, GraphQLTypes::TaskInterface, null: true
      field :annotation_type, GraphQLTypes::AnnotationType, null: true
    end
  end
end
