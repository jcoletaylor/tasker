# typed: false
# frozen_string_literal: true

require_relative 'events/definition_loader'

module Tasker
  # Constants used throughout the Tasker gem
  #
  # This module contains constants for workflow step and task statuses,
  # validation states, and configuration schemas.
  #
  # Event constants are generated from YAML definitions in config/tasker/system_events.yml
  # Run `rake tasker:generate_constants` to regenerate after YAML changes.
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

    # Task lifecycle event constants
    module TaskEvents
      INITIALIZE_REQUESTED = 'task.initialize_requested'
      START_REQUESTED = 'task.start_requested'
      COMPLETED = 'task.completed'
      FAILED = 'task.failed'
      RETRY_REQUESTED = 'task.retry_requested'
      CANCELLED = 'task.cancelled'
      RESOLVED_MANUALLY = 'task.resolved_manually'
      BEFORE_TRANSITION = 'task.before_transition'
    end

    # Step lifecycle event constants
    module StepEvents
      INITIALIZE_REQUESTED = 'step.initialize_requested'
      EXECUTION_REQUESTED = 'step.execution_requested'
      BEFORE_HANDLE = 'step.before_handle'
      HANDLE = 'step.handle'
      COMPLETED = 'step.completed'
      FAILED = 'step.failed'
      RETRY_REQUESTED = 'step.retry_requested'
      CANCELLED = 'step.cancelled'
      RESOLVED_MANUALLY = 'step.resolved_manually'
      BEFORE_TRANSITION = 'step.before_transition'
    end

    # Workflow orchestration event constants
    module WorkflowEvents
      TASK_STARTED = 'workflow.task_started'
      TASK_COMPLETED = 'workflow.task_completed'
      TASK_FAILED = 'workflow.task_failed'
      STEP_COMPLETED = 'workflow.step_completed'
      STEP_FAILED = 'workflow.step_failed'
      VIABLE_STEPS_DISCOVERED = 'workflow.viable_steps_discovered'
      NO_VIABLE_STEPS = 'workflow.no_viable_steps'
      ORCHESTRATION_REQUESTED = 'workflow.orchestration_requested'
      TASK_FINALIZATION_STARTED = 'workflow.task_finalization_started'
      TASK_FINALIZATION_COMPLETED = 'workflow.task_finalization_completed'
      TASK_REENQUEUE_STARTED = 'workflow.task_reenqueue_started'
      TASK_REENQUEUE_REQUESTED = 'workflow.task_reenqueue_requested'
      TASK_REENQUEUE_FAILED = 'workflow.task_reenqueue_failed'
      TASK_REENQUEUE_DELAYED = 'workflow.task_reenqueue_delayed'
      TASK_STATE_UNCLEAR = 'workflow.task_state_unclear'
      STEP_EXECUTION_FAILED = 'workflow.step_execution_failed'
      VIABLE_STEPS_BATCH_READY = 'workflow.viable_steps_batch_ready'
      STEPS_EXECUTION_STARTED = 'workflow.steps_execution_started'
      STEPS_EXECUTION_COMPLETED = 'workflow.steps_execution_completed'
    end

    # Observability and telemetry event constants
    module ObservabilityEvents
      # Task-level observability events
      module Task
        HANDLE = 'observability.task.handle'
        ENQUEUE = 'observability.task.enqueue'
        FINALIZE = 'observability.task.finalize'
      end

      # Step-level observability events
      module Step
        HANDLE = 'observability.step.handle'
        FIND_VIABLE = 'observability.step.find_viable'
        BACKOFF = 'observability.step.backoff'
        SKIP = 'observability.step.skip'
        MAX_RETRIES_REACHED = 'observability.step.max_retries_reached'
      end
    end

    # Test event constants
    module TestEvents
      BASIC_EVENT = 'test.event'
      SLOW_EVENT = 'slow.event'
      TEST_EVENT = 'test.event'
      CUSTOM_EVENT = 'custom.event'
      # Alternative casing event for testing
      TEST_DOT_EVENT = 'Test.Event'
    end
  end
end
