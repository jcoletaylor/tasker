# typed: strict
# frozen_string_literal: true

module Tasker
  module GraphQLTypes
    class BaseObject < GraphQL::Schema::Object
      field_class GraphQLTypes::BaseField
    end
  end
end
