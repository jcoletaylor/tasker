# typed: strict
# frozen_string_literal: true

module Tasker
  module Queries
    class TasksByStatus < BaseQuery
      include Helpers
      type [Types::TaskType], null: true

      description 'Find and sort tasks by status'
      argument :status, String, required: true
      argument :limit, Integer, default_value: 20, prepare: ->(limit, _ctx) { [limit, 100].min }, required: false
      argument :offset, Integer, default_value: 0, required: false
      argument :sort_by, String, default_value: :requested_at, required: false
      argument :sort_order, String, default_value: :desc, required: false

      sig { params(limit: T.nilable(Integer), offset: T.nilable(Integer), sort_by: T.nilable(T.any(String, Symbol)), sort_order: T.nilable(T.any(String, Symbol)), status: T.any(String, Symbol)).returns(ActiveRecord::Relation) }
      def resolve(limit:, offset:, sort_by:, sort_order:, status:)
        sorts = page_sort_params(Task, limit, offset, sort_by, sort_order)
        Tasker::Task.with_all_associated.where(status: status).limit(sorts[:limit]).offset(sorts[:offset]).order(sorts[:order])
      end
    end
  end
end
