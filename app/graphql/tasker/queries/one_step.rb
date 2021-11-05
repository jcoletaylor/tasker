# typed: strict
# frozen_string_literal: true

module Tasker
  module Queries
    class OneStep < BaseQuery
      include Helpers
      type Types::WorkflowStepType, null: true

      description 'Find a task by ID'
      description 'Find a step by taskId and ID'
      argument :task_id, Integer, required: true
      argument :step_id, ID, required: true

      sig { params(task_id: T.any(Integer, String), step_id: T.any(Integer, String)).returns(Tasker::WorkflowStep) }
      def resolve(task_id:, step_id:)
        step_query_base.where({ task_id: task_id, workflow_step_id: step_id }).first
      end
    end
  end
end
