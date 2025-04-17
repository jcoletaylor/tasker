# typed: false
# frozen_string_literal: true

module Tasker
  module Queries
    class OneStep < BaseQuery
      include Helpers
      type Tasker::GraphQLTypes::WorkflowStepType, null: true

      description 'Find a task by ID'
      description 'Find a step by taskId and ID'
      argument :task_id, Integer, required: true
      argument :step_id, ID, required: true

      def resolve(task_id:, step_id:)
        Tasker::WorkflowStep
          .includes(:named_step)
          .includes(:task)
          .where({ task_id: task_id, workflow_step_id: step_id })
          .first
      end
    end
  end
end
