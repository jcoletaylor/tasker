# typed: false
# frozen_string_literal: true

module Tasker
  module Queries
    class OneTask < BaseQuery
      include Helpers
      type Tasker::GraphQLTypes::TaskType, null: true

      description 'Find a task by ID'
      argument :task_id, ID, required: true

      def resolve(task_id:)
        Tasker::Task.extract_associated.where(task_id: task_id).first
      end
    end
  end
end
