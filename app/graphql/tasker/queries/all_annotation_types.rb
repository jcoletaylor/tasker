# typed: strict
# frozen_string_literal: true

module Tasker
  module Queries
    class AllAnnotationTypes < BaseQuery
      include Helpers
      type [Types::AnnotationType], null: true

      description 'List Annotation Types'

      sig { returns(T.untyped) }
      def resolve
        AnnotationType.order('name asc')
      end
    end
  end
end
