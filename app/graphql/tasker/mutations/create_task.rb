# typed: false
# frozen_string_literal: true

module Tasker
  module Mutations
    class CreateTask < BaseMutation
      type Tasker::GraphQLTypes::TaskType

      argument :name, String, required: true
      argument :context, GraphQL::Types::JSON, required: true
      argument :initiator, String, required: false
      argument :source_system, String, required: false
      argument :reason, String, required: false
      argument :tags, [String], required: false
      argument :bypass_steps, [String], required: false

      field :task, Tasker::GraphQLTypes::TaskType, null: false
      field :errors, [String], null: false

      def resolve(**task_params)
        context = JSON.parse(task_params.fetch(:context, '{}'))
        task_request = Tasker::Types::TaskRequest.new(task_params.merge({ context: context }))
        task = nil
        begin
          handler = handler_factory.get(task_request.name)
          task = handler.initialize_task!(task_request)
        rescue Tasker::ProceduralError => e
          task = Tasker::Task.new
          task.errors.add(:name, e.to_s)
        end

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
