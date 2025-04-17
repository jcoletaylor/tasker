# typed: false
# frozen_string_literal: true

module Tasker
  # Constants used throughout the Tasker gem
  #
  # This module contains constants for workflow step and task statuses,
  # validation states, and configuration schemas.
  module Constants
    # Status values for workflow steps
    module WorkflowStepStatuses
      # Step is waiting to be processed
      PENDING = 'pending'
      # Step is currently being processed
      IN_PROGRESS = 'in_progress'
      # Step encountered an error during processing
      ERROR = 'error'
      # Step completed successfully
      COMPLETE = 'complete'
      # Step was manually marked as resolved
      RESOLVED_MANUALLY = 'resolved_manually'
      # Step was cancelled
      CANCELLED = 'cancelled'
    end

    # Status values for tasks
    module TaskStatuses
      # Task is waiting to be processed
      PENDING = 'pending'
      # Task is currently being processed
      IN_PROGRESS = 'in_progress'
      # Task encountered an error during processing
      ERROR = 'error'
      # Task completed successfully
      COMPLETE = 'complete'
      # Task was manually marked as resolved
      RESOLVED_MANUALLY = 'resolved_manually'
      # Task was cancelled
      CANCELLED = 'cancelled'
    end

    # All valid status values for workflow steps
    VALID_WORKFLOW_STEP_STATUSES = [
      WorkflowStepStatuses::PENDING,
      WorkflowStepStatuses::IN_PROGRESS,
      WorkflowStepStatuses::ERROR,
      WorkflowStepStatuses::COMPLETE,
      WorkflowStepStatuses::CANCELLED,
      WorkflowStepStatuses::RESOLVED_MANUALLY
    ].freeze

    # Status values for steps that are not ready to be processed
    UNREADY_WORKFLOW_STEP_STATUSES = [
      WorkflowStepStatuses::IN_PROGRESS,
      WorkflowStepStatuses::COMPLETE,
      WorkflowStepStatuses::CANCELLED,
      WorkflowStepStatuses::RESOLVED_MANUALLY
    ].freeze

    # All valid status values for tasks
    VALID_TASK_STATUSES = [
      TaskStatuses::PENDING,
      TaskStatuses::IN_PROGRESS,
      TaskStatuses::ERROR,
      TaskStatuses::COMPLETE,
      TaskStatuses::CANCELLED,
      TaskStatuses::RESOLVED_MANUALLY
    ].freeze

    # Step status values that indicate completion (success or otherwise)
    VALID_STEP_COMPLETION_STATES = [
      WorkflowStepStatuses::COMPLETE,
      WorkflowStepStatuses::RESOLVED_MANUALLY,
      WorkflowStepStatuses::CANCELLED
    ].freeze

    # Step status values that indicate the step is still in a working state
    VALID_STEP_STILL_WORKING_STATES = [WorkflowStepStatuses::PENDING, WorkflowStepStatuses::IN_PROGRESS].freeze

    # Default value for unknown identifiers
    UNKNOWN = 'unknown'

    # JSON schema for validating task handler YAML configurations
    YAML_SCHEMA = {
      type: 'object',
      required: %w[name task_handler_class step_templates],
      properties: {
        name: { type: 'string' },
        module_namespace: { type: 'string', default: nil },
        task_handler_class: { type: 'string' },
        concurrent: { type: 'boolean', default: true },
        default_dependent_system: { type: 'string' },
        named_steps: {
          type: 'array',
          items: { type: 'string' }
        },
        schema: { type: 'object' },
        step_templates: {
          type: 'array',
          items: {
            type: 'object',
            required: %w[name handler_class],
            properties: {
              dependent_system: { type: 'string' },
              name: { type: 'string' },
              description: { type: 'string' },
              default_retryable: { type: 'boolean' },
              default_retry_limit: { type: 'integer' },
              skippable: { type: 'boolean' },
              handler_class: { type: 'string' },
              depends_on_step: { type: 'string' },
              depends_on_steps: {
                type: 'array',
                items: { type: 'string' }
              },
              handler_config: { type: 'object' }
            }
          }
        },
        environments: {
          type: 'object',
          additionalProperties: {
            type: 'object',
            properties: {
              step_templates: {
                type: 'array',
                items: {
                  type: 'object',
                  required: %w[name],
                  properties: {
                    name: { type: 'string' },
                    handler_config: { type: 'object' }
                  }
                }
              }
            }
          }
        }
      }
    }.freeze
  end
end
