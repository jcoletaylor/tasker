# typed: strict
# frozen_string_literal: true

module Tasker
  module Types
    class BaseEdge < Types::BaseObject
      # add `node` and `cursor` fields, as well as `node_type(...)` override
      include GraphQL::Types::Relay::EdgeBehaviors
    end
  end
end
