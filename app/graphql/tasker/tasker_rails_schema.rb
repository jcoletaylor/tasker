# typed: false
# frozen_string_literal: true

require_relative 'graph_ql_types'

module Tasker
  class TaskerRailsSchema < GraphQL::Schema
    mutation(Tasker::GraphQLTypes::MutationType)
    query(Tasker::GraphQLTypes::QueryType)

    # Union and Interface Resolution
    def self.resolve_type(abstract_type, obj, _ctx)
      case abstract_type.graphql_name
      when 'TaskInterface'
        # TaskInterface is only implemented by TaskType
        if obj.is_a?(Tasker::Task) || (obj.is_a?(Hash) && obj.key?(:named_task_id))
          GraphQLTypes::TaskType
        else
          raise "Unable to resolve TaskInterface for object: #{obj.class}"
        end
      else
        raise "Unknown abstract type: #{abstract_type.graphql_name}"
      end
    end

    # Relay-style Object Identification:

    # Return a string UUID for `object`
    def self.id_from_object(object, type_definition, query_ctx)
      # Here's a simple implementation which:
      # - joins the type name & object.id
      # - encodes it with base64:
      # GraphQL::Schema::UniqueWithinType.encode(type_definition.name, object.id)
    end

    # Given a string UUID, find the object
    def self.object_from_id(id, query_ctx)
      # For example, to decode the UUIDs generated above:
      # type_name, item_id = GraphQL::Schema::UniqueWithinType.decode(id)
      #
      # Then, based on `type_name` and `id`
      # find an object in your application
      # ...
    end
  end
end
