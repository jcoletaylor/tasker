# typed: false
# frozen_string_literal: true

module Tasker
  module Queries
    module Helpers
      def page_sort_params(model:, limit:, offset:, sort_by:, sort_order:)
        valid_sorts = model.column_names.map(&:to_sym)
        sort_by = :created_at if valid_sorts.exclude?(sort_by.to_s.to_sym)
        sort_order = :asc if %i[asc desc].exclude?(sort_order.to_s.to_sym)
        order = { sort_by => sort_order }
        { limit: limit.presence || 20, offset: offset.presence || 0, order: order }
      end
    end
  end
end
