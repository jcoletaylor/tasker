# typed: false
# frozen_string_literal: true

module Tasker
  module Queries
    class TasksByAnnotation < BaseQuery
      include Helpers
      type [Tasker::GraphQLTypes::TaskType], null: true

      description 'Find and sort tasks by status'
      argument :annotation_type, String, required: true
      argument :annotation_key, String, required: true
      argument :annotation_value, String, required: true
      argument :limit, Integer, default_value: 20, prepare: ->(limit, _ctx) { [limit, 100].min }, required: false
      argument :offset, Integer, default_value: 0, required: false
      argument :sort_by, String, default_value: :requested_at, required: false
      argument :sort_order, String, default_value: :desc, required: false

      def resolve(limit:, offset:, sort_by:, sort_order:, annotation_type:, annotation_key:, annotation_value:)
        sorts = page_sort_params(model: Tasker::Task, limit: limit, offset: offset, sort_by: sort_by,
                                 sort_order: sort_order)
        Tasker::Task
          .with_all_associated
          .by_annotation(annotation_type, annotation_key, annotation_value)
          .limit(sorts[:limit])
          .offset(sorts[:offset])
          .order(sorts[:order])
      end
    end
  end
end
