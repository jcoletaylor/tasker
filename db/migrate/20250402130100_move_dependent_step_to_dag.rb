# frozen_string_literal: true

class MoveDependentStepToDag < ActiveRecord::Migration[7.2]
  def up
    Tasker::WorkflowStep.where.not(depends_on_step_id: nil).find_each do |step|
      step.depends_on_step.add_provides_edge!(step)
    end
  end

  def down
    # pass, because we are not destroying any data
  end
end
