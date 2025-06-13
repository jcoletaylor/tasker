# frozen_string_literal: true

module Tasker
  # ActiveRecord model backed by the active step readiness status view
  # This provides fast operational queries for steps from incomplete tasks only
  class ActiveStepReadinessStatus < ApplicationRecord
    self.table_name = 'tasker_active_step_readiness_statuses'
    self.primary_key = 'workflow_step_id'

    # Associations
    belongs_to :workflow_step, class_name: 'Tasker::WorkflowStep'
    belongs_to :task, class_name: 'Tasker::Task'

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
    scope :all_steps_ready, -> { ready_for_execution.includes(:task, :workflow_step) }
    scope :blocked_by_dependencies, -> { pending.where(dependencies_satisfied: false) }
    scope :with_retry_limit, ->(limit) { where('retry_limit > ?', limit) }
    scope :with_backoff, -> { where.not(backoff_request_seconds: nil) }
    scope :with_last_attempted, -> { where.not(last_attempted_at: nil) }
    scope :ready_steps_for_task, lambda { |task_id|
      for_task(task_id).ready_for_execution.includes(:task, :workflow_step)
    }
    scope :high_attempts, lambda { |threshold = 3|
      where(attempts: threshold..)
    }
    scope :has_dependencies, lambda {
      where('total_parents > 0')
    }
    scope :dependencies_met, lambda {
      where('total_parents = completed_parents')
    }

    # Instance methods - delegate to view-calculated fields
    def ready_to_execute?
      ready_for_execution?
    end

    def has_dependencies?
      total_parents.positive?
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
