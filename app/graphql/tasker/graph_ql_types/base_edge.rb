# typed: false
# frozen_string_literal: true

module Tasker
  module GraphQLTypes
    class BaseEdge < GraphQL::Schema::Object
      include GraphQL::Types::Relay::EdgeBehaviors
    end
  end
end
