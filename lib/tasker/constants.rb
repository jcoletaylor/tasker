# typed: true
# frozen_string_literal: true

module Tasker
  module Constants
    module WorkflowStepStatuses
      PENDING = 'pending'
      IN_PROGRESS = 'in_progress'
      ERROR = 'error'
      COMPLETE = 'complete'
      RESOLVED_MANUALLY = 'resolved_manually'
      CANCELLED = 'cancelled'
    end

    module TaskStatuses
      PENDING = 'pending'
      IN_PROGRESS = 'in_progress'
      ERROR = 'error'
      COMPLETE = 'complete'
      RESOLVED_MANUALLY = 'resolved_manually'
      CANCELLED = 'cancelled'
    end

    VALID_WORKFLOW_STEP_STATUSES = [
      WorkflowStepStatuses::PENDING,
      WorkflowStepStatuses::IN_PROGRESS,
      WorkflowStepStatuses::ERROR,
      WorkflowStepStatuses::COMPLETE,
      WorkflowStepStatuses::CANCELLED,
      WorkflowStepStatuses::RESOLVED_MANUALLY
    ].freeze

    VALID_TASK_STATUSES = [
      TaskStatuses::PENDING,
      TaskStatuses::IN_PROGRESS,
      TaskStatuses::ERROR,
      TaskStatuses::COMPLETE,
      TaskStatuses::CANCELLED,
      TaskStatuses::RESOLVED_MANUALLY
    ].freeze

    VALID_STEP_COMPLETION_STATES = [
      WorkflowStepStatuses::COMPLETE,
      WorkflowStepStatuses::RESOLVED_MANUALLY,
      WorkflowStepStatuses::CANCELLED
    ].freeze

    VALID_STEP_STILL_WORKING_STATES = [WorkflowStepStatuses::PENDING, WorkflowStepStatuses::IN_PROGRESS].freeze
    UNKNOWN = 'unknown'
  end
end
