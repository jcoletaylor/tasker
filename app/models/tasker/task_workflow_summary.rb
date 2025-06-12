# frozen_string_literal: true

module Tasker
  # ActiveRecord model backed by the task workflow summary view
  # This provides enhanced workflow analysis for active tasks only
  class TaskWorkflowSummary < ApplicationRecord
    self.table_name = 'tasker_task_workflow_summaries'
    self.primary_key = 'task_id'

    # Associations
    belongs_to :task, class_name: 'Tasker::Task', foreign_key: 'task_id'

    # Scopes using view-calculated fields
    scope :optimal, -> { where(workflow_efficiency: 'optimal') }
    scope :recovering, -> { where(workflow_efficiency: 'recovering') }
    scope :blocked, -> { where(workflow_efficiency: 'blocked') }
    scope :processing, -> { where(workflow_efficiency: 'processing') }
    scope :waiting, -> { where(workflow_efficiency: 'waiting') }

    # Parallelism insight scopes (descriptive, not prescriptive)
    scope :high_parallelism, -> { where(parallelism_potential: 'high_parallelism') }
    scope :moderate_parallelism, -> { where(parallelism_potential: 'moderate_parallelism') }
    scope :sequential_only, -> { where(parallelism_potential: 'sequential_only') }
    scope :no_ready_work, -> { where(parallelism_potential: 'no_ready_work') }

    # Workflow complexity scopes
    scope :simple_workflows, -> { where('max_dependency_depth <= 2') }
    scope :complex_workflows, -> { where('max_dependency_depth > 5 OR parallel_branches > 3') }
    scope :highly_parallel, -> { where('parallel_branches > 3') }

    # Efficiency scopes (corresponding to instance methods)
    scope :efficient, -> { where(workflow_efficiency: ['optimal', 'recovering', 'processing']) }
    scope :has_parallelism_potential, -> { where(parallelism_potential: ['high_parallelism', 'moderate_parallelism']) }
    scope :has_ready_work, -> { where('ready_steps > 0') }

    # Class methods for workflow analysis
    class << self
      # Get workflow summary for a specific task
      def for_task(task_id)
        find_by(task_id: task_id)
      end

      # Get tasks with parallelism potential (insights, not directives)
      def with_parallelism_opportunities
        has_parallelism_potential.where(workflow_efficiency: ['optimal', 'recovering'])
      end

      # Get tasks that need attention
      def needs_intervention
        where(workflow_efficiency: 'blocked')
      end

      # Performance monitoring - get inefficient workflows
      def inefficient_workflows
        where(workflow_efficiency: ['blocked', 'waiting'])
          .where('ready_steps = 0')
      end
    end

    # Instance methods for workflow analysis
    def efficient?
      workflow_efficiency.in?(['optimal', 'recovering', 'processing'])
    end

    def has_parallelism_potential?
      parallelism_potential.in?(['high_parallelism', 'moderate_parallelism'])
    end

    def is_complex_workflow?
      max_dependency_depth > 5 || parallel_branches > 3
    end

    def has_ready_work?
      ready_steps > 0
    end

    def workflow_health_summary
      {
        efficiency: workflow_efficiency,
        parallelism_potential: parallelism_potential,
        complexity: {
          max_depth: max_dependency_depth,
          parallel_branches: parallel_branches,
          is_complex: is_complex_workflow?
        },
        readiness: {
          ready_steps: ready_steps,
          blocked_steps: blocked_step_ids&.length || 0,
          can_process: has_ready_work?
        }
      }
    end

    def step_analysis
      {
        root_steps: {
          ids: root_step_ids || [],
          count: root_step_count || 0
        },
        ready_steps: {
          ids: ready_step_ids || [],
          count: ready_steps
        },
        blocked_steps: {
          ids: blocked_step_ids || [],
          reasons: blocking_reasons || []
        }
      }
    end

    # Parallelism insights (descriptive analysis, not processing directives)
    def parallelism_analysis
      {
        potential: parallelism_potential,
        ready_step_count: ready_steps,
        description: case parallelism_potential
                     when 'high_parallelism'
                       "#{ready_steps} steps ready - high parallelism opportunity"
                     when 'moderate_parallelism'
                       "#{ready_steps} steps ready - moderate parallelism opportunity"
                     when 'sequential_only'
                       "#{ready_steps} step ready - sequential processing only"
                     else
                       'No steps ready for processing'
                     end
      }
    end

    # Read-only model - prevent modifications
    def readonly?
      true
    end
  end
end
