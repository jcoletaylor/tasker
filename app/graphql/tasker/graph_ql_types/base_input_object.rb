# typed: false
# frozen_string_literal: true

module Tasker
  module GraphQLTypes
    class BaseInputObject < GraphQL::Schema::InputObject
      argument_class GraphQLTypes::BaseArgument
    end
  end
end
