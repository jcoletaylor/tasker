# frozen_string_literal: true

module Tasker
  class TaskExecutionContext < ApplicationRecord
    self.table_name = 'tasker_task_execution_contexts'
    self.primary_key = 'task_id'

    # Read-only model backed by database view
    def readonly?
      true
    end

    # Associations to actual models for additional data
    belongs_to :task, inverse_of: :execution_context

    # Scopes for common queries using constants
    scope :with_ready_steps, -> { where('ready_steps > 0') }
    scope :blocked, -> { where(execution_status: Constants::TaskExecution::ExecutionStatus::BLOCKED_BY_FAILURES) }
    scope :complete, -> { where(execution_status: Constants::TaskExecution::ExecutionStatus::ALL_COMPLETE) }
    scope :healthy, -> { where(health_status: Constants::TaskExecution::HealthStatus::HEALTHY) }
    scope :in_progress, lambda {
      where(execution_status: [
              Constants::TaskExecution::ExecutionStatus::HAS_READY_STEPS,
              Constants::TaskExecution::ExecutionStatus::PROCESSING
            ])
    }
    scope :needs_attention, lambda {
      where(health_status: [
              Constants::TaskExecution::HealthStatus::BLOCKED,
              Constants::TaskExecution::HealthStatus::RECOVERING
            ])
    }

    # Helper methods for workflow decision making using constants
    def has_work_to_do?
      Constants::ACTIONABLE_TASK_EXECUTION_STATUSES.include?(execution_status) ||
        execution_status == Constants::TaskExecution::ExecutionStatus::PROCESSING
    end

    def is_blocked?
      execution_status == Constants::TaskExecution::ExecutionStatus::BLOCKED_BY_FAILURES
    end

    def is_complete?
      execution_status == Constants::TaskExecution::ExecutionStatus::ALL_COMPLETE
    end

    def is_healthy?
      health_status == Constants::TaskExecution::HealthStatus::HEALTHY
    end

    def needs_intervention?
      health_status == Constants::TaskExecution::HealthStatus::BLOCKED
    end

    def can_make_progress?
      ready_steps.positive?
    end

    def should_reenqueue?
      Constants::REENQUEUE_TASK_EXECUTION_STATUSES.include?(execution_status)
    end

    def needs_immediate_action?
      Constants::ACTIONABLE_TASK_EXECUTION_STATUSES.include?(execution_status)
    end

    # Status summary methods
    def workflow_summary
      {
        total_steps: total_steps,
        completed: completed_steps,
        pending: pending_steps,
        in_progress: in_progress_steps,
        failed: failed_steps,
        ready: ready_steps,
        completion_percentage: completion_percentage,
        status: execution_status,
        health: health_status,
        recommended_action: recommended_action
      }
    end

    def progress_details
      {
        completed_ratio: "#{completed_steps}/#{total_steps}",
        completion_percentage: "#{completion_percentage}%",
        remaining_steps: total_steps - completed_steps,
        failed_steps: failed_steps,
        ready_steps: ready_steps
      }
    end

    def next_action_details
      case recommended_action
      when Constants::TaskExecution::RecommendedAction::EXECUTE_READY_STEPS
        {
          action: Constants::TaskExecution::RecommendedAction::EXECUTE_READY_STEPS,
          description: "#{ready_steps} steps ready for execution",
          urgency: 'high',
          can_proceed: true
        }
      when Constants::TaskExecution::RecommendedAction::WAIT_FOR_COMPLETION
        {
          action: Constants::TaskExecution::RecommendedAction::WAIT_FOR_COMPLETION,
          description: "#{in_progress_steps} steps currently processing",
          urgency: 'low',
          can_proceed: false
        }
      when Constants::TaskExecution::RecommendedAction::HANDLE_FAILURES
        {
          action: Constants::TaskExecution::RecommendedAction::HANDLE_FAILURES,
          description: "#{failed_steps} failed steps blocking progress",
          urgency: 'critical',
          can_proceed: false
        }
      when Constants::TaskExecution::RecommendedAction::FINALIZE_TASK
        {
          action: Constants::TaskExecution::RecommendedAction::FINALIZE_TASK,
          description: 'All steps completed successfully',
          urgency: 'medium',
          can_proceed: true
        }
      else
        {
          action: Constants::TaskExecution::RecommendedAction::WAIT_FOR_DEPENDENCIES,
          description: 'Waiting for dependencies to be satisfied',
          urgency: 'low',
          can_proceed: false
        }
      end
    end

    # Class methods for batch operations using constants
    def self.ready_for_processing
      with_ready_steps.where.not(execution_status: Constants::TaskExecution::ExecutionStatus::BLOCKED_BY_FAILURES)
    end

    def self.requiring_intervention
      where(health_status: Constants::TaskExecution::HealthStatus::BLOCKED)
    end

    def self.making_progress
      where(execution_status: [
              Constants::TaskExecution::ExecutionStatus::HAS_READY_STEPS,
              Constants::TaskExecution::ExecutionStatus::PROCESSING
            ])
    end

    # Performance optimization - use active view for operational queries
    def self.active
      Tasker::ActiveTaskExecutionContext
    end
  end
end
