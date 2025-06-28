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
      # Use existing WorkflowStepEdge siblings logic - finds steps with exact same parent set
      # This is more accurate than just shared parents and leverages well-tested code
      WorkflowStepEdge.siblings_of(object).pluck(:to_step_id)
    end
  end
end
