# typed: false
# frozen_string_literal: true

module Tasker
  module GraphQLTypes
    class BaseField < GraphQL::Schema::Field
      argument_class GraphQLTypes::BaseArgument
    end
  end
end
