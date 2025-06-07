# typed: false
# frozen_string_literal: true

require_dependency 'tasker/application_controller'

module Tasker
  class TasksController < ApplicationController
    include PageSort
    include Tasker::Concerns::Authenticatable

    before_action :set_task, only: %i[update destroy]
    before_action :set_full_task, only: %i[show]
    before_action :set_page_sort_params, only: %i[index]

    # GET /tasks
    def index
      @tasks =
        query_base.limit(page_sort_params[:limit]).offset(page_sort_params[:offset]).order(page_sort_params[:order]).all
      render(json: @tasks, status: :ok, adapter: :json, root: :tasks, each_serializer: Tasker::TaskSerializer)
    end

    # GET /tasks/1
    def show
      render(json: @task, status: :ok, adapter: :json, root: :task, serializer: Tasker::TaskSerializer)
    end

    # POST /tasks
    def create
      if task_params_as_symbolized_hash[:name].blank?
        return render(status: :bad_request,
                      json: { error: 'invalid parameters: requires task name' })
      end
      set_task_request
      begin
        handler = handler_factory.get(@task_request.name)
        @task = handler.initialize_task!(@task_request)
      rescue Tasker::ProceduralError => e
        @task = Tasker::Task.new
        @task.errors.add(:name, e.to_s)
      end

      # we don't want to re-run save here because it will remove the
      # context validation from the handler and check "valid?"
      if @task.errors.empty?
        render(json: @task, status: :created, adapter: :json, root: :task, serializer: Tasker::TaskSerializer)
      else
        render(status: :bad_request, json: { error: @task.errors })
      end
    end

    # PATCH/PUT /tasks/1
    def update
      if @task.update(update_task_params)
        render(json: @task, status: :ok, adapter: :json, root: :task, serializer: Tasker::TaskSerializer)
      else
        render(json: { error: @task.errors }, status: :unprocessable_entity)
      end
    end

    # DELETE /tasks/1
    def destroy
      # Use state machine to transition task to cancelled
      @task.state_machine.transition_to!(Tasker::Constants::TaskStatuses::CANCELLED)
      render(status: :ok, json: { cancelled: true })
    end

    private

    def set_task
      @task = Tasker::Task.find(params[:id])
    end

    def set_full_task
      @task = query_base.find(params[:id])
    end

    def task_params
      params.require(:task).permit(:name, :initiator, :source_system, :reason, tags: [], context: {})
    end

    def update_task_params
      params.require(:task).permit(:reason, tags: [])
    end

    def set_page_sort_params
      build_page_sort_params('Tasker::Task', :task_id)
    end

    def handler_factory
      @handler_factory ||= Tasker::HandlerFactory.instance
    end

    def query_base
      Tasker::Task.with_all_associated
    end

    def task_params_as_symbolized_hash
      task_params.to_h.deep_symbolize_keys
    end

    def set_task_request
      @task_request = Tasker::Types::TaskRequest.new(task_params_as_symbolized_hash)
    end
  end
end
