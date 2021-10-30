# typed: strict
# frozen_string_literal: true

module Tasker
  module Types
    class BaseField < GraphQL::Schema::Field
      argument_class Types::BaseArgument
    end
  end
end
