# frozen_string_literal: true

module Tasker
  class WorkflowStepEdge < ApplicationRecord
    belongs_to :from_step, class_name: 'WorkflowStep'
    belongs_to :to_step, class_name: 'WorkflowStep'

    validates :name, uniqueness: { scope: [:from_step_id, :to_step_id] }

    validates :name, presence: true

    scope :children_of, ->(step) { where(from_step: step) }
    scope :parents_of, ->(step) { where(to_step: step) }

    scope :siblings_of, ->(step) { find_by_sql(sibling_sql(step.id)) }

    scope :provides_edges, -> { where(name: WorkflowStep::PROVIDES_EDGE_NAME) }
    scope :depends_on_edges, -> { where(name: WorkflowStep::DEPENDS_ON_EDGE_NAME) }

    def self.create_edge!(from_step, to_step, name)
      create!(from_step: from_step, to_step: to_step, name: name)
    end

    def self.sibling_sql(step_id)
      "WITH step_parents AS (
        SELECT from_step_id
        FROM tasker_workflow_step_edges
        WHERE to_step_id = #{step_id}
      ),
      potential_siblings AS (
        SELECT to_step_id
        FROM tasker_workflow_step_edges
        WHERE from_step_id IN (SELECT from_step_id FROM step_parents)
        AND to_step_id != #{step_id}
      )
      SELECT e.*
      FROM tasker_workflow_step_edges e
      JOIN (
        SELECT to_step_id
        FROM tasker_workflow_step_edges
        WHERE to_step_id IN (SELECT to_step_id FROM potential_siblings)
        GROUP BY to_step_id
        HAVING ARRAY_AGG(from_step_id ORDER BY from_step_id) =
              (SELECT ARRAY_AGG(from_step_id ORDER BY from_step_id) FROM step_parents)
      ) siblings ON e.to_step_id = siblings.to_step_id
      "
    end
  end
end
