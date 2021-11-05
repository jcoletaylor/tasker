# typed: strict
# frozen_string_literal: true

module Tasker
  module Types
    class MutationType < Types::BaseObject
      field :create_task, mutation: Mutations::CreateTask
      field :update_task, mutation: Mutations::UpdateTask
      field :cancel_task, mutation: Mutations::CancelTask

      field :cancel_step, mutation: Mutations::CancelStep
      field :update_step, mutation: Mutations::UpdateStep
    end
  end
end
