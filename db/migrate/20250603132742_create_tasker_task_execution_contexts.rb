# frozen_string_literal: true

class CreateTaskerTaskExecutionContexts < ActiveRecord::Migration[7.2]
  def change
    create_view :tasker_task_execution_contexts
  end
end
