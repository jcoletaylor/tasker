# typed: strict
# frozen_string_literal: true

module Tasker
  module Types
    class QueryType < Types::BaseObject
      description 'The query root of the Tasker schema'

      include GraphQL::Types::Relay::HasNodeField
      include GraphQL::Types::Relay::HasNodesField

      field :tasks, resolver: Queries::AllTasks
      field :tasks_by_status, resolver: Queries::TasksByStatus
      field :tasks_by_annotation, resolver: Queries::TasksByAnnotation
      field :task, resolver: Queries::OneTask
      field :step, resolver: Queries::OneStep
      field :annotation_types, resolver: Queries::AllAnnotationTypes
    end
  end
end
