# typed: false
# frozen_string_literal: true

module Tasker
  module GraphQLTypes
    module TaskInterface
      include GraphQL::Schema::Interface

      field :task_id, ID, null: false
      field :status, String, null: false
      field :reason, String, null: true
      field :tags, GraphQL::Types::JSON, null: true
      field :created_at, GraphQL::Types::ISO8601DateTime, null: false
      field :updated_at, GraphQL::Types::ISO8601DateTime, null: false
    end
  end
end
