# typed: strict
# frozen_string_literal: true

module Tasker
  class WorkflowStepSerializer < ActiveModel::Serializer
    attributes :task_id, :workflow_step_id, :name, :named_step_id, :status, :attempts, :skippable,
               :retryable, :retry_limit, :processed, :processed_at, :in_process, :backoff_request_seconds,
               :last_attempted_at, :inputs, :results,
               :children_ids, :parents_ids, :siblings_ids

    def children_ids
      object.children.pluck(:workflow_step_id)
    end

    def parents_ids
      object.parents.pluck(:workflow_step_id)
    end

    def siblings_ids
      object.siblings.pluck(:workflow_step_id)
    end
  end
end
