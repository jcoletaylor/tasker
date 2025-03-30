class MoveDependentStepToAncestry < ActiveRecord::Migration[7.2]
  def up
    Tasker::WorkflowStep.where.not(depends_on_step_id: nil).find_each do |step|
      parent_step = step.depends_on_step
      step.update!(parent: parent_step)
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
