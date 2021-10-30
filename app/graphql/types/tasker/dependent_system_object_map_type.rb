# typed: strict
# frozen_string_literal: true

module Tasker
  module Types
    class DependentSystemObjectMapType < Types::BaseObject
      field :dependent_system_object_map_id, ID, null: false
      field :dependent_system_one_id, Integer, null: false
      field :dependent_system_two_id, Integer, null: false
      field :remote_id_one, String, null: false
      field :remote_id_two, String, null: false
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
      field :dependent_system_one, Types::DependentSystemType, null: true
      field :dependent_system_two, Types::DependentSystemType, null: true
    end
  end
end
