# typed: false
# frozen_string_literal: true

module Tasker
  module Mutations
    class UpdateTask < BaseMutation
      ALLOWED_UPDATE_FIELDS = %i[reason tags].freeze
      type Tasker::GraphQLTypes::TaskType

      argument :task_id, ID, required: true
      argument :reason, String, required: false
      argument :tags, [String], required: false

      field :task, Tasker::GraphQLTypes::TaskType, null: false
      field :errors, [String], null: false

      def resolve(task_id:, **args)
        task = Tasker::Task.find(task_id)
        params = {}
        args.each do |key, val|
          params[key] = val if key.to_sym.in?(ALLOWED_UPDATE_FIELDS)
        end
        task.update!(params) unless params.empty?

        # we don't want to re-run save here because it will remove the
        # context validation from the handler and check "valid?"
        if task.errors.empty?
          Tasker::TaskSerializer.new(task).to_hash
        else
          { task: nil, errors: task.errors }
        end
      end

      private

      def handler_factory
        @handler_factory ||= Tasker::HandlerFactory.instance
      end
    end
  end
end
