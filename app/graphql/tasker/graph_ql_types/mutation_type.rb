# typed: strict
# frozen_string_literal: true

module Tasker
  module GraphQLTypes
    class MutationType < GraphQLTypes::BaseObject
      description 'Entry point to all mutation data'

      field :create_task, mutation: Mutations::CreateTask
      field :update_task, mutation: Mutations::UpdateTask
      field :cancel_task, mutation: Mutations::CancelTask
      field :update_step, mutation: Mutations::UpdateStep
      field :cancel_step, mutation: Mutations::CancelStep
    end
  end
end
