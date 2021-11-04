# typed: strict
# frozen_string_literal: true

module Tasker
  module Queries
    class BaseQuery < GraphQL::Schema::Resolver
      extend T::Sig
    end
  end
end
