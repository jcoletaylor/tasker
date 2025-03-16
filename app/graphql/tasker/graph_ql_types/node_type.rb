# typed: strict
# frozen_string_literal: true

module Tasker
  module GraphQLTypes
    module NodeType
      include GraphQLTypes::BaseInterface
      # Add the `id` field
      include GraphQL::Types::Relay::NodeBehaviors
    end
  end
end
