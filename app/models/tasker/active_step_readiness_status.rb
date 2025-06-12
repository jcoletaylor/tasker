# frozen_string_literal: true

module Tasker
  # ActiveRecord model backed by the active step readiness status view
  # This provides fast operational queries for steps from incomplete tasks only
  class ActiveStepReadinessStatus < ApplicationRecord
    self.table_name = 'tasker_active_step_readiness_statuses'
    self.primary_key = 'workflow_step_id'

    # Associations
    belongs_to :workflow_step, class_name: 'Tasker::WorkflowStep', foreign_key: 'workflow_step_id'
    belongs_to :task, class_name: 'Tasker::Task', foreign_key: 'task_id'

    # Scopes for common query patterns - using view-calculated fields
    scope :ready_for_execution, -> { where(ready_for_execution: true) }
    scope :pending, -> { where(current_state: 'pending') }
    scope :in_progress, -> { where(current_state: 'in_progress') }
    scope :failed, -> { where(current_state: 'error') }
    scope :completed, -> { where(current_state: 'complete') }

    # Use view-calculated fields instead of duplicating business logic
    scope :retry_eligible, -> { where(retry_eligible: true) }
    scope :dependencies_satisfied, -> { where(dependencies_satisfied: true) }
    scope :with_failures, -> { where('attempts > 0') }

    # Scopes for task-level filtering
    scope :for_task, ->(task_id) { where(task_id: task_id) }
    scope :for_tasks, ->(task_ids) { where(task_id: task_ids) }

    # Class methods for common operations
    class << self
      # Get all ready steps across all active tasks
      def all_ready_steps
        ready_for_execution.includes(:workflow_step, :task)
      end

      # Get ready steps for a specific task
      def ready_steps_for_task(task_id)
        for_task(task_id).ready_for_execution
      end

      # Get steps blocked by dependencies
      def blocked_by_dependencies
        pending.where(dependencies_satisfied: false)
      end

      # Performance monitoring - get steps with many retries
      def high_retry_steps(threshold = 3)
        where('attempts >= ?', threshold)
      end
    end

    # Instance methods - delegate to view-calculated fields
    def ready_to_execute?
      ready_for_execution?
    end

    def has_dependencies?
      total_parents > 0
    end

    def dependencies_met?
      dependencies_satisfied?
    end

    # Summary methods using view-calculated data
    def retry_summary
      {
        attempts: attempts,
        retry_limit: retry_limit,
        retry_eligible: retry_eligible?,
        next_retry_at: next_retry_at,
        last_failure_at: last_failure_at
      }
    end

    def dependency_summary
      {
        total_parents: total_parents,
        completed_parents: completed_parents,
        dependencies_satisfied: dependencies_satisfied?,
        remaining_dependencies: total_parents - completed_parents
      }
    end

    # Read-only model - prevent modifications
    def readonly?
      true
    end
  end
end
