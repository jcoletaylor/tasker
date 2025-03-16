# typed: strict
# frozen_string_literal: true

module Tasker
  module Mutations
    class CancelStep < BaseMutation
      type Tasker::GraphQLTypes::WorkflowStepType

      argument :task_id, ID, required: true
      argument :step_id, ID, required: true

      field :step, Tasker::GraphQLTypes::WorkflowStepType, null: false
      field :errors, [String], null: false

      sig do
        params(task_id: T.any(Integer, String), step_id: T.any(Integer, String)).returns(T::Hash[Symbol, T.untyped])
      end
      def resolve(task_id:, step_id:)
        step = Tasker::WorkflowStep.where({ task_id: task_id, workflow_step_id: step_id }).first
        return { step: nil, errors: 'no such step' } unless step

        step.update!({ status: Tasker::Constants::WorkflowStepStatuses::CANCELLED })
        if step.errors.empty?
          Tasker::WorkflowStepSerializer.new(step).to_hash
        else
          { step: nil, errors: step.errors }
        end
      end
    end
  end
end
