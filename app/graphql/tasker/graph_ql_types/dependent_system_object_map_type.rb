# typed: strict
# frozen_string_literal: true

module Tasker
  module GraphQLTypes
    class DependentSystemObjectMapType < GraphQLTypes::BaseObject
      field :dependent_system_object_map_id, ID, null: false
      field :dependent_system_one_id, Integer, null: false
      field :dependent_system_two_id, Integer, null: false
      field :remote_id_one, String, null: false
      field :remote_id_two, String, null: false
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
      field :dependent_system_one, GraphQLTypes::DependentSystemType, null: true
      field :dependent_system_two, GraphQLTypes::DependentSystemType, null: true
    end
  end
end
