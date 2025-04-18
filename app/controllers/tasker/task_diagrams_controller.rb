# typed: false
# frozen_string_literal: true

require_dependency 'tasker/application_controller'

module Tasker
  class TaskDiagramsController < ApplicationController
    before_action :set_full_task, only: %i[index]

    # GET /tasks/1/task_diagrams
    def index
      render(json: @task.diagram(request.base_url).to_json, status: :ok)
    end

    private

    def set_full_task
      @task = query_base.find(params[:task_id])
    end

    def query_base
      Tasker::Task.with_all_associated
    end
  end
end
