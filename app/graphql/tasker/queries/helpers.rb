# typed: strict
# frozen_string_literal: true

module Tasker
  module Queries
    module Helpers
      extend T::Sig

      sig { params(model: T.untyped, limit: T.nilable(Integer), offset: T.nilable(Integer), sort_by: T.nilable(T.any(String, Symbol)), sort_order: T.nilable(T.any(String, Symbol))).returns(T::Hash[Symbol, T.any(Integer, String, Symbol)]) }
      def page_sort_params(model, limit, offset, sort_by, sort_order)
        valid_sorts = model.column_names.map(&:to_sym)
        sort_by = :created_at unless valid_sorts.include?(sort_by.to_s.to_sym)
        sort_order = :asc unless %i[asc desc].include?(sort_order.to_s.to_sym)
        order = { sort_by => sort_order }
        { limit: (limit || 20).to_i, offset: (offset || 0).to_i, order: order }
      end
    end
  end
end
