# typed: strict
# frozen_string_literal: true

module Tasker
  module GraphQLTypes
    module BaseInterface
      include GraphQL::Schema::Interface
      edge_type_class(GraphQLTypes::BaseEdge)
      connection_type_class(GraphQLTypes::BaseConnection)

      field_class GraphQLTypes::BaseField
    end
  end
end
