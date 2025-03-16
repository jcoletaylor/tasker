# typed: true
# frozen_string_literal: true

module Tasker
  module Mutations
    class UpdateStep < BaseMutation
      ALLOWED_UPDATE_FIELDS = T.let(%i[retry_limit inputs].freeze, T::Array[Symbol])
      type Tasker::GraphQLTypes::WorkflowStepType

      argument :step_id, ID, required: true
      argument :task_id, Integer, required: true
      argument :retry_limit, Integer, required: false
      argument :inputs, GraphQL::Types::JSON, required: false

      field :step, Tasker::GraphQLTypes::WorkflowStepType, null: false
      field :errors, [String], null: false

      def resolve(task_id:, step_id:, **args)
        step = Tasker::WorkflowStep.where({ task_id: task_id, workflow_step_id: step_id }).first
        return { step: nil, errors: 'no such step' } unless step

        params = {}
        args.each do |key, val|
          params[key] = val if key.to_sym.in?(ALLOWED_UPDATE_FIELDS)
        end
        step.update!(params) unless params.empty?

        if step.errors.empty?
          Tasker::WorkflowStepSerializer.new(step).to_hash
        else
          { step: nil, errors: step.errors }
        end
      end
    end
  end
end
