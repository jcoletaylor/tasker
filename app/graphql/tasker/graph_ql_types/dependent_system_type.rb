# typed: false
# frozen_string_literal: true

module Tasker
  module GraphQLTypes
    class DependentSystemType < GraphQLTypes::BaseObject
      field :dependent_system_id, ID, null: false
      field :name, String, null: false
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
    end
  end
end
