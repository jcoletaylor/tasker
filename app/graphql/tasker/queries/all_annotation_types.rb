# typed: false
# frozen_string_literal: true

module Tasker
  module Queries
    class AllAnnotationTypes < BaseQuery
      include Helpers
      type [Tasker::GraphQLTypes::AnnotationType], null: true

      description 'List Annotation Types'

      def resolve
        AnnotationType.order('name asc')
      end
    end
  end
end
