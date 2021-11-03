# typed: strict
# frozen_string_literal: true

module Tasker
  module Mutations
    class CancelTask < BaseMutation
      type Types::TaskType

      argument :task_id, ID, required: true

      field :task, Types::TaskType, null: false
      field :errors, [String], null: false

      def resolve(task_id:)
        @task = Tasker::Task.find(task_id)
        @task.update({ status: Tasker::Constants::TaskStatuses::CANCELLED })

        # we don't want to re-run save here because it will remove the
        # context validation from the handler and check "valid?"
        if @task.errors.empty?
          Tasker::TaskSerializer.new(@task).to_hash
        else
          { task: nil, errors: @task.errors }
        end
      end
    end
  end
end
