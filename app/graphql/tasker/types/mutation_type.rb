# typed: true
# frozen_string_literal: true

module Tasker
  module Types
    class MutationType < Types::BaseObject
      field :create_task, mutation: Mutations::CreateTask
    end
  end
end
