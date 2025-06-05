module Tasker
  class TaskExecutionContext < ApplicationRecord
    self.table_name = 'tasker_task_execution_contexts'
    self.primary_key = 'task_id'

    # Read-only model backed by database view
    def readonly?
      true
    end

    # Associations to actual models for additional data
    belongs_to :task, foreign_key: 'task_id', inverse_of: :execution_context

    # Scopes for common queries
    scope :with_ready_steps, -> { where('ready_steps > 0') }
    scope :blocked, -> { where(execution_status: 'blocked_by_failures') }
    scope :complete, -> { where(execution_status: 'all_complete') }
    scope :healthy, -> { where(health_status: 'healthy') }
    scope :in_progress, -> { where(execution_status: %w[has_ready_steps processing]) }
    scope :needs_attention, -> { where(health_status: %w[blocked recovering]) }

    # Helper methods for workflow decision making
    def has_work_to_do?
      %w[has_ready_steps processing].include?(execution_status)
    end

    def is_blocked?
      execution_status == 'blocked_by_failures'
    end

    def is_complete?
      execution_status == 'all_complete'
    end

    def is_healthy?
      health_status == 'healthy'
    end

    def needs_intervention?
      health_status == 'blocked'
    end

    def can_make_progress?
      ready_steps > 0
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
      when 'execute_ready_steps'
        {
          action: 'execute_ready_steps',
          description: "#{ready_steps} steps ready for execution",
          urgency: 'high',
          can_proceed: true
        }
      when 'wait_for_completion'
        {
          action: 'wait_for_completion',
          description: "#{in_progress_steps} steps currently processing",
          urgency: 'low',
          can_proceed: false
        }
      when 'handle_failures'
        {
          action: 'handle_failures',
          description: "#{failed_steps} failed steps blocking progress",
          urgency: 'critical',
          can_proceed: false
        }
      when 'finalize_task'
        {
          action: 'finalize_task',
          description: 'All steps completed successfully',
          urgency: 'medium',
          can_proceed: true
        }
      else
        {
          action: 'wait_for_dependencies',
          description: 'Waiting for dependencies to be satisfied',
          urgency: 'low',
          can_proceed: false
        }
      end
    end

    # Class methods for batch operations
    def self.ready_for_processing
      with_ready_steps.where.not(execution_status: 'blocked_by_failures')
    end

    def self.requiring_intervention
      where(health_status: 'blocked')
    end

    def self.making_progress
      where(execution_status: %w[has_ready_steps processing])
    end
  end
end
