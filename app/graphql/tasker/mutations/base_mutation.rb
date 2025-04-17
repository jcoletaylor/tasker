# typed: false
# frozen_string_literal: true

module Tasker
  module Mutations
    class BaseMutation < GraphQL::Schema::RelayClassicMutation
      argument_class Tasker::GraphQLTypes::BaseArgument
      field_class Tasker::GraphQLTypes::BaseField
      input_object_class Tasker::GraphQLTypes::BaseInputObject
      object_class Tasker::GraphQLTypes::BaseObject
    end
  end
end
