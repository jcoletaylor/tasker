# frozen_string_literal: true

module Tasker
  class StepReadinessStatus < ApplicationRecord
    self.table_name = 'tasker_step_readiness_statuses'
    self.primary_key = 'workflow_step_id'

    # Read-only model backed by database view
    def readonly?
      true
    end

    # Associations to actual models for additional data
    belongs_to :workflow_step
    belongs_to :task

    # Scopes for common queries
    scope :ready, -> { where(ready_for_execution: true) }
    scope :ready_for_execution, -> { where(ready_for_execution: true) }
    scope :blocked_by_dependencies, -> { where(dependencies_satisfied: false) }
    scope :blocked_by_retry, -> { where(retry_eligible: false) }
    scope :for_task, ->(task_id) { where(task_id: task_id) }
    scope :pending, -> { where(current_state: 'pending') }
    scope :failed, -> { where(current_state: 'failed') }
    scope :in_progress, -> { where(current_state: 'in_progress') }
    scope :complete, -> { where(current_state: 'complete') }

    # Helper methods for readiness analysis
    def can_execute_now?
      ready_for_execution
    end

    def blocking_reason
      return nil if ready_for_execution
      return 'dependencies_not_satisfied' unless dependencies_satisfied
      return 'retry_not_eligible' unless retry_eligible
      return 'invalid_state' unless %w[pending failed].include?(current_state)

      'unknown'
    end

    def time_until_ready
      return 0 if ready_for_execution
      return nil unless next_retry_at

      [(next_retry_at - Time.current).to_i, 0].max
    end

    def dependency_status
      if total_parents.zero?
        'no_dependencies'
      elsif dependencies_satisfied
        'all_satisfied'
      else
        "#{completed_parents || 0}/#{total_parents || 0}_satisfied"
      end
    end

    def retry_status
      if attempts >= retry_limit
        'max_retries_reached'
      elsif retry_eligible
        'retry_eligible'
      else
        'waiting_for_backoff'
      end
    end

    def backoff_type
      if backoff_request_seconds.present? && last_attempted_at.present?
        'explicit_backoff'
      elsif last_failure_at.present?
        'exponential_backoff'
      else
        'no_backoff'
      end
    end

    def effective_backoff_seconds
      if backoff_request_seconds.present?
        backoff_request_seconds
      elsif attempts.present? && attempts.positive?
        # Calculate default exponential backoff (base_delay * 2^attempts, capped at 30)
        [2**attempts, 30].min
      else
        0
      end
    end

    def detailed_status
      {
        ready: ready_for_execution,
        current_state: current_state,
        dependencies: dependency_status,
        retry: retry_status,
        blocking_reason: blocking_reason,
        time_until_ready: time_until_ready,
        backoff_type: backoff_type,
        effective_backoff_seconds: effective_backoff_seconds
      }
    end

    # Performance optimization - use active view for operational queries
    def self.active
      Tasker::ActiveStepReadinessStatus
    end
  end
end
