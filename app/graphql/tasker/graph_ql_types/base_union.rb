# typed: strict
# frozen_string_literal: true

module Tasker
  module GraphQLTypes
    class BaseUnion < GraphQL::Schema::Union
      edge_type_class(GraphQLTypes::BaseEdge)
      connection_type_class(GraphQLTypes::BaseConnection)
    end
  end
end
