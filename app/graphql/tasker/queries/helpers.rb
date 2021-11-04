# typed: strict
# frozen_string_literal: true

module Tasker
  module Queries
    module Helpers
      extend T::Sig

      sig { returns(ActiveRecord::Relation) }
      def task_query_base
        Tasker::Task.includes(:named_task)
                    .includes(workflow_steps: %i[named_step depends_on_step])
                    .includes(task_annotations: %i[annotation_type])
      end

      sig { returns(ActiveRecord::Relation) }
      def step_query_base
        Tasker::WorkflowStep.includes(:named_step).includes(:task)
      end

      sig { params(model: T.untyped, limit: T.nilable(Integer), offset: T.nilable(Integer), sort_by: T.nilable(T.any(String, Symbol)), sort_order: T.nilable(T.any(String, Symbol))).returns(T::Hash[Symbol, T.any(Integer, String, Symbol)]) }
      def page_sort_params(model, limit, offset, sort_by, sort_order)
        valid_sorts = model.column_names.map(&:to_sym)
        sort_by = :created_at unless valid_sorts.include?(sort_by)
        sort_order = :asc unless %i[asc desc].include?(sort_order)
        order = { sort_by => sort_order }
        { limit: (limit || 20).to_i, offset: (offset || 0).to_i, order: order }
      end
    end
  end
end
