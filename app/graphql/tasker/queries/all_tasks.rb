# typed: strict
# frozen_string_literal: true

module Tasker
  module Queries
    class AllTasks < BaseQuery
      include Helpers
      type [Tasker::GraphQLTypes::TaskType], null: true

      description 'Find and sort tasks'
      argument :limit, Integer, default_value: 20, prepare: ->(limit, _ctx) { [limit, 100].min }, required: false
      argument :offset, Integer, default_value: 0, required: false
      argument :sort_by, String, default_value: :requested_at, required: false
      argument :sort_order, String, default_value: :desc, required: false

      sig do
        params(limit: T.nilable(Integer), offset: T.nilable(Integer), sort_by: T.nilable(T.any(String, Symbol)),
               sort_order: T.nilable(T.any(String, Symbol))).returns(T.untyped)
      end
      def resolve(limit:, offset:, sort_by:, sort_order:)
        sorts = page_sort_params(model: Tasker::Task, limit: limit, offset: offset, sort_by: sort_by,
                                 sort_order: sort_order)
        Tasker::Task.with_all_associated.limit(sorts[:limit]).offset(sorts[:offset]).order(sorts[:order])
      end
    end
  end
end
