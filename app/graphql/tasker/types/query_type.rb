# typed: true
# frozen_string_literal: true

module Tasker
  module Types
    class QueryType < Types::BaseObject
      description 'The query root of the Tasker schema'

      include GraphQL::Types::Relay::HasNodeField
      include GraphQL::Types::Relay::HasNodesField

      field :tasks, resolver: Queries::AllTasks
      field :tasks_by_status, resolver: Queries::TasksByStatus
      field :task, resolver: Queries::OneTask
      field :step, resolver: Queries::OneStep
    end
  end
end
