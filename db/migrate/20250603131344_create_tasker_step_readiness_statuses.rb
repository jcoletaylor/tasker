class CreateTaskerStepReadinessStatuses < ActiveRecord::Migration[7.2]
  def change
    create_view :tasker_step_readiness_statuses
  end
end
