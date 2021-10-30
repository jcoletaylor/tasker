# typed: strict
# frozen_string_literal: true

module Tasker
  module Types
    module NodeType
      include Types::BaseInterface
      # Add the `id` field
      include GraphQL::Types::Relay::NodeBehaviors
    end
  end
end
