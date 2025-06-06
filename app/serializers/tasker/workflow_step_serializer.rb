# typed: false
# frozen_string_literal: true

module Tasker
  class WorkflowStepSerializer < ActiveModel::Serializer
    attributes :task_id, :workflow_step_id, :name, :named_step_id, :status, :attempts, :skippable,
               :retryable, :retry_limit, :processed, :processed_at, :in_process, :backoff_request_seconds,
               :last_attempted_at, :inputs, :results,
               :children_ids, :parents_ids, :siblings_ids

    def children_ids
      # Use scenic view for efficient parent/child lookups - eliminates N+1 queries
      object.step_dag_relationship&.child_step_ids_array || []
    end

    def parents_ids
      # Use scenic view for efficient parent/child lookups - eliminates N+1 queries
      object.step_dag_relationship&.parent_step_ids_array || []
    end

    def siblings_ids
      # Siblings are more complex - get all children of this step's parents, excluding self
      # For now, fall back to original pattern but add comment for future optimization
      object.siblings.pluck(:workflow_step_id)
      # TODO: Optimize siblings using DAG view - need to aggregate sibling relationships
    end
  end
end
