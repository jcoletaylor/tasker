# typed: false
# frozen_string_literal: true

module Tasker
  module GraphQLTypes
    class NamedTaskType < GraphQLTypes::BaseObject
      field :named_task_id, ID, null: false
      field :name, String, null: false
      field :description, String, null: true
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
    end
  end
end
