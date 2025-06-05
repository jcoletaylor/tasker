class CreateTaskerStepDagRelationships < ActiveRecord::Migration[7.2]
  def change
    create_view :tasker_step_dag_relationships
  end
end
