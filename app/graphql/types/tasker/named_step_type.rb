# typed: strict
# frozen_string_literal: true

module Tasker
  module Types
    class NamedStepType < Types::BaseObject
      field :named_step_id, ID, null: false
      field :dependent_system_id, Integer, null: false
      field :name, String, null: false
      field :description, String, null: true
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
      field :dependent_system, Types::DependentSystemType, null: true
    end
  end
end
