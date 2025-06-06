# frozen_string_literal: true

module Tasker
  class TaskWorkflowSummary < ApplicationRecord
    self.table_name = 'tasker_task_workflow_summaries'
    self.primary_key = 'task_id'

    # Read-only model backed by database view
    def readonly?
      true
    end

    # Associations to actual models for additional data
    belongs_to :task, inverse_of: :task_workflow_summary

    # Scopes for common workflow analysis queries
    scope :with_ready_steps, -> { where('ready_steps > 0') }
    scope :blocked, -> { where(execution_status: 'blocked_by_failures') }
    scope :complete, -> { where(execution_status: 'all_complete') }
    scope :in_progress, -> { where(execution_status: %w[has_ready_steps processing]) }
    scope :requiring_batch_processing, -> { where(processing_strategy: 'batch_parallel') }
    scope :requiring_parallel_processing, -> { where(processing_strategy: %w[batch_parallel small_parallel]) }

    # Helper methods for workflow analysis
    def has_work_to_do?
      %w[has_ready_steps processing].include?(execution_status)
    end

    def is_blocked?
      execution_status == 'blocked_by_failures'
    end

    def is_complete?
      execution_status == 'all_complete'
    end

    def requires_parallel_processing?
      %w[batch_parallel small_parallel].include?(processing_strategy)
    end

    def requires_batch_processing?
      processing_strategy == 'batch_parallel'
    end

    # Parse JSONB arrays for step IDs
    def root_step_ids_array
      return [] if root_step_ids.blank?

      root_step_ids.is_a?(Array) ? root_step_ids : JSON.parse(root_step_ids)
    end

    def next_executable_step_ids_array
      return [] if next_executable_step_ids.blank?

      next_executable_step_ids.is_a?(Array) ? next_executable_step_ids : JSON.parse(next_executable_step_ids)
    end

    def blocked_step_ids_array
      return [] if blocked_step_ids.blank?

      blocked_step_ids.is_a?(Array) ? blocked_step_ids : JSON.parse(blocked_step_ids)
    end

    def blocking_reasons_array
      return [] if blocking_reasons.blank?

      blocking_reasons.is_a?(Array) ? blocking_reasons : JSON.parse(blocking_reasons)
    end

    # Business logic helpers
    def next_steps_for_processing
      case processing_strategy
      when 'batch_parallel'
        next_executable_step_ids_array.take(10) # Process up to 10 steps in parallel
      when 'small_parallel'
        next_executable_step_ids_array.take(3)  # Process up to 3 steps in parallel
      when 'sequential'
        next_executable_step_ids_array.take(1)  # Process 1 step at a time
      else
        []
      end
    end

    def processing_recommendation
      {
        strategy: processing_strategy,
        step_ids: next_steps_for_processing,
        parallel_safe: requires_parallel_processing?,
        batch_size: next_steps_for_processing.size
      }
    end
  end
end
